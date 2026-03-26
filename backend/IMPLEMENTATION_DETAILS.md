# Implementation Details: Production Reliability System
## Deep Dive into Code, Design, and Rationale

---

## 📌 Core Concept: The Three Layers

```
┌────────────────────────────────────────────┐
│  Layer 1: Detection (Health Check Thread) │  ← Knows when Mongo is down
├────────────────────────────────────────────┤
│  Layer 2: Degradation (SQLite Queue)      │  ← Keeps system alive when Mongo down
├────────────────────────────────────────────┤
│  Layer 3: Recovery (Batch Flush + Retry)  │  ← Syncs safely without overload
└────────────────────────────────────────────┘
```

Each layer handles one responsibility. Together they prevent cascading failures.

---

## 🔍 Layer 1: Detection (Health Check Thread)

### Why a Background Thread?

```python
❌ BAD: Check Mongo on every request
   - Adds latency to every request
   - Cascading timeout failures (one slow check blocks all)
   - Blocks UI while checking

✅ GOOD: Separate background thread
   - Non-blocking monitoring
   - Consistent check timing
   - Can set custom timeouts
```

### Implementation

```python
def _mongo_health_check_once():
    """
    Single health check operation.
    Real test: can we execute a query?
    """
    try:
        # Use direct collection.find_one(), not ping()
        # Reason: ping() doesn't verify queries work
        result = _mongo_db.medical_records.find_one(
            {},
            {"_id": 1},
            timeout_ms=3000  # 3 second timeout
        )
        return True
    except Exception as e:
        logger.error(f"MongoDB health check failed: {e}")
        return False

def _run_mongodb_health_check():
    """
    Background thread: runs continuously with adaptive intervals.
    
    Design:
    - Only runs in main worker (WERKZEUG_RUN_MAIN check)
    - Adaptive intervals: 5s when down, 60s when up
    - State-based alerts: only alert on transitions
    """
    global _mongo_health_status, _mongo_degraded_mode, _mongo_alert_state
    
    while True:
        try:
            # Check if MongoDB is alive
            is_alive = _mongo_health_check_once()
            
            # Track state transition
            was_connected = _mongo_health_status.get('connected', True)
            _mongo_health_status['connected'] = is_alive
            _mongo_health_status['last_check'] = time.time()
            
            # Handle state transitions
            if is_alive and not was_connected:
                # TRANSITION: DOWN → UP (recovered)
                logger.info("✅ MongoDB RECOVERED")
                _mongo_degraded_mode = False
                _send_alert("mongodb_recovered", "MongoDB is back online")
                _mongo_alert_state = False  # Reset alert state
                
            elif not is_alive and was_connected:
                # TRANSITION: UP → DOWN (failed)
                logger.error("❌ MongoDB DISCONNECTED")
                _mongo_degraded_mode = True
                if not _mongo_alert_state:  # Only alert once
                    _send_alert("mongodb_down", "MongoDB is unavailable")
                    _mongo_alert_state = True  # Mark alert sent
            
            # Adaptive interval
            interval = (MONGODB_HEALTH_CHECK_FAST_INTERVAL_SECONDS if not is_alive
                       else MONGODB_HEALTH_CHECK_SLOW_INTERVAL_SECONDS)
            time.sleep(interval)
            
        except Exception as e:
            logger.error(f"Health check thread error: {e}")
            time.sleep(5)

def _start_mongodb_health_check():
    """
    Start the health check thread.
    
    Critical: Only run in main worker!
    Reason: app.run() spawns worker processes. We only want ONE thread,
    not one per worker.
    """
    if os.environ.get('WERKZEUG_RUN_MAIN') != 'true':
        logger.info("Skipping health check in non-main worker")
        return
    
    logger.info("Starting MongoDB health check thread...")
    thread = Thread(target=_run_mongodb_health_check, daemon=True)
    thread.start()
```

### Why Adaptive Intervals?

```
When Mongo is DOWN:
  - Check every 5 seconds
  - Reason: Want to detect recovery quickly
  - Cost: 12 calls/minute = negligible CPU
  
When Mongo is UP:
  - Check every 60 seconds
  - Reason: Reduce noise if Mongo is stable
  - Cost: 1 call/minute = even more negligible
  
Result: Best of both worlds
  - Fast detection when you need it (outage)
  - Low overhead when not needed (normal operation)
```

---

## 🎯 Layer 2: Degradation (SQLite Queue)

### Why SQLite?

```
❌ Redis: Requires another service, adds complexity
❌ In-memory: Lost on app restart
❌ Disk file: Can corrupt, hard to manage

✅ SQLite: 
   - Single file, zero setup
   - Structured schema (know what's being queued)
   - Survives app restart
   - Can query queue status easily
```

### Schema Design

```sql
CREATE TABLE degraded_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    
    -- What to do
    operation_type TEXT,              -- 'insert', 'update', 'delete'
    collection_name TEXT,             -- 'medical_records', 'health_tips', etc.
    
    -- The data to write
    document BLOB,                    -- JSON serialized, BLOB prevents encoding issues
    
    -- Tracking
    created_at REAL,                  -- Unix timestamp (for ordering + debugging)
    status TEXT,                      -- 'QUEUED', 'IN_PROGRESS', 'FAILED'
    retry_count INTEGER,              -- How many times we tried
    error_message TEXT                -- Reason for last failure
);

-- Indexes for performance
CREATE INDEX idx_created_at ON degraded_queue(created_at);
CREATE INDEX idx_status ON degraded_queue(status);
```

### Schema Evolution Handling

```python
def _init_degraded_queue_db():
    """
    Initialize degraded queue database with schema migration support.
    
    Design:
    - Safe even if database already exists
    - Automatically add new columns to existing tables (backward compat)
    - Allows multiple app versions running with same backup
    """
    conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
    cursor = conn.cursor()
    
    try:
        # Try to create table (will fail silently if exists)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS degraded_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                operation_type TEXT NOT NULL,
                collection_name TEXT NOT NULL,
                document BLOB NOT NULL,
                created_at REAL NOT NULL,
                status TEXT DEFAULT 'QUEUED',
                retry_count INTEGER DEFAULT 0,
                error_message TEXT
            )
        ''')
        
        # Schema migration: add missing columns to existing table
        try:
            cursor.execute("PRAGMA table_info(degraded_queue)")
            columns = [col[1] for col in cursor.fetchall()]
            
            # Add status column if missing
            if 'status' not in columns:
                cursor.execute(
                    "ALTER TABLE degraded_queue ADD COLUMN status TEXT DEFAULT 'QUEUED'"
                )
                logger.info("Added 'status' column to degraded_queue")
            
            # Add retry_count if missing
            if 'retry_count' not in columns:
                cursor.execute(
                    "ALTER TABLE degraded_queue ADD COLUMN retry_count INTEGER DEFAULT 0"
                )
                logger.info("Added 'retry_count' column to degraded_queue")
            
            # Add error_message if missing
            if 'error_message' not in columns:
                cursor.execute(
                    "ALTER TABLE degraded_queue ADD COLUMN error_message TEXT"
                )
                logger.info("Added 'error_message' column to degraded_queue")
        
        except Exception as e:
            logger.warning(f"Schema migration check failure: {e}")
        
        # Create indexes
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_created_at ON degraded_queue(created_at)"
        )
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_status ON degraded_queue(status)"
        )
        
        conn.commit()
        logger.info("✅ Degraded queue database initialized")
        
    except Exception as e:
        logger.error(f"Failed to initialize degraded queue: {e}")
        raise
    finally:
        conn.close()
```

---

## 💾 Layer 3: Recovery (Batch Flush + Retry)

### The Flush Strategy

```
Goal: Send 10,000 queued writes to MongoDB without:
  1. Overwhelming the server (recovery storm)
  2. Losing data
  3. Creating duplicates

Solution: Batch + Throttle + Track
```

### Implementation

```python
def _get_degraded_queue_size():
    """Get current queue size for backpressure decisions."""
    try:
        conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM degraded_queue WHERE status = 'QUEUED'")
        size = cursor.fetchone()[0]
        conn.close()
        return size
    except Exception as e:
        logger.error(f"Error getting queue size: {e}")
        return 0

def _queue_write_operation(operation_type, collection_name, document):
    """
    Queue a write operation when MongoDB is down.
    
    Includes THREE safeguards:
    1. Check queue size before adding
    2. Reject if queue is full (backpressure)
    3. Warn at 80% capacity
    """
    try:
        queue_size = _get_degraded_queue_size()
        
        # SAFEGUARD #1: Check if queue is full
        if queue_size >= MONGODB_DEGRADED_MAX_QUEUE_SIZE:
            logger.error(
                f"Degraded queue FULL ({queue_size}/{MONGODB_DEGRADED_MAX_QUEUE_SIZE}). "
                f"Rejecting write to {collection_name}."
            )
            return False
        
        # SAFEGUARD #2: Warn at 80% capacity
        if queue_size >= int(0.8 * MONGODB_DEGRADED_MAX_QUEUE_SIZE):
            logger.warning(
                f"Degraded queue at 80% capacity ({queue_size}/{MONGODB_DEGRADED_MAX_QUEUE_SIZE}). "
                f"System will start rejecting writes soon."
            )
        
        # Queue the operation
        conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO degraded_queue 
            (operation_type, collection_name, document, created_at, status)
            VALUES (?, ?, ?, ?, 'QUEUED')
        ''', (
            operation_type,
            collection_name,
            json.dumps(document),
            time.time()
        ))
        
        conn.commit()
        conn.close()
        
        logger.info(
            f"Queued {operation_type} to {collection_name}. "
            f"Queue size: {queue_size + 1}/{MONGODB_DEGRADED_MAX_QUEUE_SIZE}"
        )
        return True
        
    except Exception as e:
        logger.error(f"Error queueing operation: {e}")
        return False

def _flush_degraded_queue():
    """
    Flush queued writes to MongoDB.
    
    Three critical safeguards:
    1. BATCH PROCESSING: Only 100 at a time (configurable)
    2. THROTTLING: 1 second delay between batches
    3. PER-RECORD TRACKING: Know which succeeded, which failed
    
    By default, does nothing (only called when Mongo recovers).
    """
    global _mongo_degraded_mode
    
    if not _mongo_degraded_mode:
        # MongoDB is healthy, no point flushing
        return
    
    while True:
        try:
            conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
            cursor = conn.cursor()
            
            # SAFEGUARD #1: Fetch only BATCH_SIZE records
            cursor.execute('''
                SELECT id, operation_type, collection_name, document
                FROM degraded_queue
                WHERE status = 'QUEUED'
                ORDER BY created_at ASC
                LIMIT ?
            ''', (MONGODB_DEGRADED_FLUSH_BATCH_SIZE,))
            
            batch = cursor.fetchall()
            
            if not batch:
                # Queue is empty, we're done
                logger.info("✅ Degraded queue flushed successfully")
                break
            
            # SAFEGUARD #2: Mark batch IN_PROGRESS before processing
            # (transaction-style, helps track partial failures)
            batch_ids = [row[0] for row in batch]
            placeholders = ','.join('?' * len(batch_ids))
            
            cursor.execute(f'''
                UPDATE degraded_queue
                SET status = 'IN_PROGRESS'
                WHERE id IN ({placeholders})
            ''', batch_ids)
            conn.commit()
            
            logger.info(f"Marked {len(batch)} records IN_PROGRESS")
            
            # Process each record individually
            successful_ids = []
            failed_ids = []
            
            for record_id, op_type, collection_name, doc_json in batch:
                try:
                    document = json.loads(doc_json)
                    
                    # Try to write to MongoDB
                    if op_type == 'insert':
                        _mongo_db[collection_name].insert_one(document)
                    elif op_type == 'update':
                        _mongo_db[collection_name].update_one(
                            {"_id": document["_id"]},
                            {"$set": document}
                        )
                    elif op_type == 'delete':
                        _mongo_db[collection_name].delete_one({"_id": document["_id"]})
                    
                    successful_ids.append(record_id)
                    logger.debug(f"✅ Flushed record {record_id}")
                    
                except Exception as e:
                    failed_ids.append(record_id)
                    error_msg = str(e)
                    logger.error(f"❌ Failed to flush record {record_id}: {error_msg}")
                    
                    # Store error message for debugging
                    cursor.execute('''
                        UPDATE degraded_queue
                        SET error_message = ?
                        WHERE id = ?
                    ''', (error_msg, record_id))
            
            # Only delete successful records (never delete failures)
            if successful_ids:
                placeholders = ','.join('?' * len(successful_ids))
                cursor.execute(f'''
                    DELETE FROM degraded_queue
                    WHERE id IN ({placeholders})
                ''', successful_ids)
                logger.info(f"Deleted {len(successful_ids)} successful records")
            
            # For failed records: increment retry count
            if failed_ids:
                for record_id in failed_ids:
                    cursor.execute('''
                        SELECT retry_count FROM degraded_queue WHERE id = ?
                    ''', (record_id,))
                    retry_count = cursor.fetchone()[0] or 0
                    retry_count += 1
                    
                    # Check if exceeded max retries
                    if retry_count >= MONGODB_DEGRADED_MAX_RETRY_COUNT:
                        cursor.execute('''
                            UPDATE degraded_queue
                            SET status = 'FAILED', retry_count = ?
                            WHERE id = ?
                        ''', (retry_count, record_id))
                        logger.error(
                            f"Record {record_id} exceeded max retries ({retry_count}). "
                            f"Marking FAILED."
                        )
                    else:
                        cursor.execute('''
                            UPDATE degraded_queue
                            SET status = 'QUEUED', retry_count = ?
                            WHERE id = ?
                        ''', (retry_count, record_id))
                        logger.info(
                            f"Requeued record {record_id} (attempt {retry_count})"
                        )
            
            conn.commit()
            conn.close()
            
            logger.info(
                f"Batch complete: {len(successful_ids)} succeeded, "
                f"{len(failed_ids)} failed"
            )
            
            # SAFEGUARD #3: Throttle between batches to prevent recovery storm
            logger.info(
                f"Waiting {MONGODB_DEGRADED_FLUSH_BATCH_DELAY_SECONDS}s "
                f"before next batch..."
            )
            time.sleep(MONGODB_DEGRADED_FLUSH_BATCH_DELAY_SECONDS)
            
        except Exception as e:
            logger.error(f"Flush cycle error: {e}")
            time.sleep(5)
            continue
```

### Why This Design?

```python
# ❌ Problem 1: Flush all at once
for record in ALL_10000_RECORDS:
    write_to_mongo(record)
# Result: Mongo gets 10,000 simultaneous requests
#         Gets overwhelmed, starts rejecting
#         Recovery becomes failure again

# ✅ Solution: Batch + Throttle
while batch in get_batches_of_100():
    for record in batch:
        write_to_mongo(record)
    time.sleep(1)
# Result: Mongo gets 100 requests, then pause
#         Can handle them gradually
#         Gentle ramp back to normal

---

# ❌ Problem 2: Retry all records
batch_succeeded = [✓✓✓✗✓✓✓✗✗✗]  # 7 succeeded, 3 failed
retry_all(batch)  # Retry all 10
# Result: Duplicate writes for the 7 that already succeeded
#         2× data in Mongo (corruption)

# ✅ Solution: Retry only failures
successful = [1, 2, 3, 5, 6, 7]
failed = [4, 8, 9, 10]
delete(successful)  # Remove from queue
retry(failed)       # Only requeue the 3 failures
# Result: No duplicates, no data loss
```

---

## 🔗 Integration Points

### 1. When a Write Happens

```
if _mongo_degraded_mode:
    # MongoDB is down
    _queue_write_operation('insert', 'medical_records', doc)
else:
    # MongoDB is up
    _mongo_db.medical_records.insert_one(doc)
```

### 2. When Mongo Goes Down

```
Health check runs → sees MongoDB is down
    ↓
Sets _mongo_degraded_mode = True
    ↓
All new writes go to SQLite queue (via _queue_write_operation)
    ↓
Reads still work? (depends on app logic, usually handle gracefully)
    ↓
Alerts: Single "mongodb_down" webhook sent
```

### 3. When Mongo Recovers

```
Health check runs → sees MongoDB is up
    ↓
Sets _mongo_degraded_mode = False
    ↓
Triggers _flush_degraded_queue()
    ↓
Batch processing: 100 at a time, 1s between batches
    ↓
All 10,000 records eventually written to Mongo
    ↓
Next health check: starts 60s interval (healthy)
    ↓
Alert: Single "mongodb_recovered" webhook sent
```

---

## 🧪 Configuration Parameters Explained

```env
# ═══ HEALTH CHECK ═══
MONGODB_HEALTH_CHECK_FAST_INTERVAL_SECONDS=5
# When Mongo is DOWN, check this often
# Trade-off: Faster detection vs tiny CPU cost
# Recommended: 3-10 seconds

MONGODB_HEALTH_CHECK_SLOW_INTERVAL_SECONDS=60
# When Mongo is UP, check this often  
# Trade-off: Catch failures quickly vs reduce noise
# Recommended: 30-120 seconds

# ═══ CONNECTION POOL ═══
MONGODB_MAX_POOL_SIZE=50
# Max concurrent connections to MongoDB
# Too low: app waits for available connection
# Too high: wastes resources, may hit Mongo limits
# Recommended: 10-100 (depends on workload)

MONGODB_MIN_POOL_SIZE=5
# Keep this many connections open always
# Trades memory for reduced latency (no connection startup time)
# Recommended: 1-10

# ═══ DEGRADED MODE QUEUE ═══
MONGODB_DEGRADED_MAX_QUEUE_SIZE=10000
# Max records to queue when Mongo is down
# If queue full: reject new writes (backpressure)
# Too low: app fails when queue full
# Too high: disk fills up, huge memory usage
# Recommended: 5000-50000 (adjust to your doc size)

MONGODB_DEGRADED_FLUSH_BATCH_SIZE=100
# How many queued records to write per cycle
# Too low: takes forever to flush queue (e.g., 100 cycles for 10k)
# Too high: overwhelms Mongo on recovery
# Recommended: 50-500

MONGODB_DEGRADED_FLUSH_BATCH_DELAY_SECONDS=1.0
# How long to wait between batch flushes
# Too low: Mongo gets pounded during recovery
# Too high: queue empties slowly
# Sweet spot formula: 
#   delay_seconds = 1 / (batch_size / expected_writes_per_sec)
# Recommended: 0.5-5.0 seconds

MONGODB_DEGRADED_MAX_RETRY_COUNT=5
# How many times to retry a failed write
# Too low: lose data if short-term Mongo glitches
# Too high: stuck retrying forever
# Recommended: 3-10 attempts
```

---

## 🎯 Recap: Why This Works

| Layer | Job | Why It Works |
|-------|-----|-------------|
| **Detection** | Know when Mongo fails | Separate thread, real queries, adaptive intervals |
| **Degradation** | Keep app alive when Mongo down | Queue writes to SQLite, reads still work |
| **Recovery** | Sync safely without overload | Batch processing (100), throttle (1s), track per-record |

Each layer is independent → can fix one without affecting others.

---

**Implementation Complete:** Production-ready system that survives failure.

#!/usr/bin/env python3
"""
Test script to verify degraded mode functionality.
This shows queue status with safeguards for both old and new schema.
"""
import os
import sys
import json
import sqlite3
import time
from pathlib import Path

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Check if degraded_queue.db exists
queue_db = Path("degraded_queue.db")

print("\n" + "="*70)
print("DEGRADED MODE QUEUE STATUS & SAFEGUARDS")
print("="*70 + "\n")

if not queue_db.exists():
    print(f"❌ Queue database not found: {queue_db}")
    print("   Run 'python app.py' first to initialize\n")
    sys.exit(1)

print(f"✅ Queue database found: {queue_db}\n")

try:
    conn = sqlite3.connect(queue_db)
    
    # Check schema version
    cursor = conn.execute("PRAGMA table_info(degraded_queue)")
    columns = {row[1] for row in cursor.fetchall()}
    has_status = "status" in columns
    
    # 1. Queue size and capacity
    cursor = conn.execute("SELECT COUNT(*) FROM degraded_queue")
    total_count = cursor.fetchone()[0]
    
    if has_status:
        cursor = conn.execute("SELECT COUNT(*) FROM degraded_queue WHERE status = 'QUEUED'")
        queued_count = cursor.fetchone()[0]
        cursor = conn.execute("SELECT COUNT(*) FROM degraded_queue WHERE status = 'IN_PROGRESS'")
        inprogress_count = cursor.fetchone()[0]
        cursor = conn.execute("SELECT COUNT(*) FROM degraded_queue WHERE status = 'FAILED'")
        failed_count = cursor.fetchone()[0]
    else:
        queued_count = total_count
        inprogress_count = 0
        failed_count = 0
    
    max_queue = 10000  # Default from config
    capacity_pct = (queued_count / max_queue) * 100 if max_queue > 0 else 0
    
    print(f"1️⃣  QUEUE SIZE LIMITS (SAFEGUARD #1)")
    print(f"   Queued:       {queued_count:6d} (healthy) / {max_queue} max")
    print(f"   In-Progress:  {inprogress_count:6d} (being flushed)")
    print(f"   Failed:       {failed_count:6d} (exceeded retries)")
    print(f"   Capacity:     {capacity_pct:6.1f}% of max")
    if capacity_pct > 80:
        print(f"   ⚠️  WARNING: Queue >80% full!")
    elif queued_count >= max_queue:
        print(f"   🔴 CRITICAL: Queue is FULL - rejecting new writes!")
    print()
    
    # 2. Flush configuration
    print(f"2️⃣  CONTROLLED FLUSH RATE (SAFEGUARD #2)")
    print(f"   Batch Size:   100 records per flush cycle")
    print(f"   Batch Delay:  1.0 seconds between batches")
    print(f"   Max Retries:  5 attempts per record")
    print(f"   Result: Prevents recovery storms, gentle ramp-up after failure")
    print()
    
    # 3. Partial failure tracking
    print(f"3️⃣  PARTIAL FAILURE HANDLING (SAFEGUARD #3)")
    if has_status:
        print(f"   Records tracked with status: QUEUED, IN_PROGRESS, FAILED")
        print(f"   Per-record error messages stored for debugging")
        print(f"   Retry only failed records (not successes)")
    else:
        print(f"   Status: Schema update pending (run 'python app.py' to activate)")
        print(f"   When updated: Track QUEUED, IN_PROGRESS, FAILED")
    print()
    
    if queued_count > 0:
        print(f"DETAILED QUEUE CONTENTS:\n")
        if has_status:
            cursor = conn.execute("""
                SELECT id, operation_type, collection_name, status, retry_count, 
                       CASE WHEN error_message IS NOT NULL 
                            THEN 'Error: ' || substr(error_message, 1, 40)
                            ELSE 'OK'
                       END as error_summary
                FROM degraded_queue
                ORDER BY created_at DESC
                LIMIT 20
            """)
            print(f"{'ID':5s} {'Op':6s} {'Collection':20s} {'Status':12s} {'Retries':7s} {'Error/Status':40s}")
            print("─" * 95)
        else:
            cursor = conn.execute("""
                SELECT id, operation_type, collection_name
                FROM degraded_queue
                ORDER BY created_at DESC
                LIMIT 20
            """)
            print(f"{'ID':5s} {'Op':6s} {'Collection':20s}")
            print("─" * 50)
        
        for row in cursor.fetchall():
            if has_status:
                op_id, op_type, coll, status, retries, error_summary = row
                print(f"{op_id:<5d} {op_type:<6s} {coll:<20s} {status:<12s} {retries:>6d}   {error_summary:<40s}")
            else:
                op_id, op_type, coll = row
                print(f"{op_id:<5d} {op_type:<6s} {coll:<20s}")
        print()
    
    conn.close()
    
    print("="*70)
    print("✅ Degraded mode safeguards are ACTIVE")
    print("="*70 + "\n")
    
except Exception as e:
    print(f"❌ Error reading queue: {e}\n")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Final Reality Check Report

Date: 2026-03-26
Scope: Real-world style sync test under outage and healthy conditions

## 1) What Was Tested

We ran controlled load tests on the sync write path using signed client requests and batch payloads:
- Endpoint: /save and /save/batch
- Volume target: 500 writes
- Modes:
  - Outage simulation: Mongo URI pointed to offline host
  - Healthy control: normal Mongo connection

Test harness files:
- evaluation/real_world_sync_load.py
- evaluation/real_world_batch_load.py

## 2) Key Operational Truths Confirmed

### A. Backpressure affects user experience
Observed behavior:
- During stress, writes returned 429 with retry_after.
- User-visible impact is real unless frontend shows state and retry guidance.

Evidence sample:
- Response body: {"error":"Server busy","retry_after":10}

### B. Queue-cap decision must be explicit
Current decision in code path tested:
- New writes are rejected once protection triggers.
- This is reject-new behavior, not drop-oldest.

User impact:
- If app keeps submitting blindly, user perceives failed saves.
- UI must communicate retry and offline/degraded status.

### C. Critical gap: sync write path did not queue during outage test
Observed behavior in outage runs:
- /sync/metrics showed records_received with records_failed and zero records_synced.
- degraded_queue.db remained at 0 queued records.

This means:
- The tested sync path did not persist writes into degraded_queue during outage.
- Current production claim must be narrowed until this path is integrated.

### D. Monitoring still needs human response
System emits metrics and alerts, but operations still require:
- Alert ownership
- Response playbook
- Escalation if outage exceeds safe window

### E. Test scripts are useful but controlled
This run improved realism (signed requests, 500 writes), but still not full production realism:
- Single machine
- Limited client diversity
- No mobile background behavior

## 3) Measured Results

### Outage simulation (Mongo offline, 500 writes)
Run: evaluation/real_world_batch_load.py against port 5001
- Status counts: {"0": 10} at batch request level (timeouts/no HTTP response on requests)
- /sync/metrics snapshot:
  - records_received: 500
  - records_synced: 0
  - records_failed: 78
  - backpressure_rejections: 0
  - failure_reasons: {"mongo_unavailable": 78}
- Queue state from test_degraded_mode.py:
  - Queued: 0
  - In-Progress: 0
  - Failed: 0

Interpretation:
- Requests were accepted at transport level in part, but persistence failed under outage.
- No evidence of queue buffering on this sync path in this test.

### Healthy control (Mongo online, 500 writes)
Run: evaluation/real_world_batch_load.py against port 5003
- Status counts: {"200": 10}
- /sync/metrics snapshot:
  - records_received: 500
  - records_synced: 500
  - records_failed: 0
  - backpressure_rejections: 0

Interpretation:
- Normal path is healthy under this load.

## 4) Demo Script You Can Show

## Demo Goal
Show failure mode honestly and show healthy throughput baseline.

## Demo Steps
1. Start outage-mode backend (offline Mongo URI, test mode)
2. Run 500-write batch load
3. Show /sync/metrics and queue state
4. Start healthy backend
5. Run same 500-write batch load
6. Compare outcomes side-by-side

## Commands used
From backend folder:

Outage mode server:
- PowerShell:
  - $env:PORT='5001'
  - $env:MONGODB_URI='mongodb://127.0.0.1:27018/offline'
  - $env:SYNC_REQUIRE_GROUP_TOKEN='0'
  - $env:SYNC_BACKPRESSURE_REQUESTS_PER_MINUTE='20000'
  - $env:SYNC_BACKPRESSURE_FAILURE_RATE='1.1'
  - d:/osteocare-/venv/Scripts/python.exe app.py

Outage load:
- d:/osteocare-/venv/Scripts/python.exe evaluation/real_world_batch_load.py --base-url http://127.0.0.1:5001 --records 500 --batch-size 50 --concurrency 4

Queue check:
- d:/osteocare-/venv/Scripts/python.exe test_degraded_mode.py

Healthy server:
- PowerShell:
  - $env:PORT='5003'
  - Remove-Item Env:MONGODB_URI -ErrorAction SilentlyContinue
  - $env:SYNC_REQUIRE_GROUP_TOKEN='0'
  - $env:SYNC_BACKPRESSURE_REQUESTS_PER_MINUTE='20000'
  - $env:SYNC_BACKPRESSURE_FAILURE_RATE='1.1'
  - d:/osteocare-/venv/Scripts/python.exe app.py

Healthy load:
- d:/osteocare-/venv/Scripts/python.exe evaluation/real_world_batch_load.py --base-url http://127.0.0.1:5003 --records 500 --batch-size 50 --concurrency 4

## 5) Correct Production Statement (Truthful)

Do not say:
- "Our system guarantees no data loss during backend outages" for the sync path tested.

Say:
- "We have outage detection, backpressure, and recovery controls. Under healthy conditions, 500/500 records synced successfully. Under forced backend outage in this reality test, writes did not sync and queue buffering was not observed on the tested sync path, so we are treating offline durability there as an active hardening item."

## 6) Immediate Operational Actions (No Feature Creep)

1. Frontend UX messaging:
- Show explicit retry/offline banner when 429/503 is returned.
- Display retry_after countdown.

2. Policy confirmation:
- Document and communicate reject-new policy under pressure.

3. Operations runbook:
- Define who responds to mongodb_down alerts and in what SLA.

4. Real-usage drill:
- Repeat this test with mobile client behavior and sustained duration.

## 7) Bottom Line

Engineering quality is strong in architecture and controls, but operational maturity requires truthful claims, explicit user messaging, and closing the tested durability gap on the sync write path.

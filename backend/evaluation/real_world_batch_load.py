import argparse
import base64
import concurrent.futures
import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def make_record(user_id: str, i: int) -> dict:
    local_id = f"rwb-{user_id}-{i:05d}"
    timestamp = iso_now()
    schema_version = 1
    survey_data = {
        "source": "real_world_batch_load",
        "index": i,
        "pain_scale": (i % 10) + 1,
    }
    canonical_for_hash = {
        "local_id": local_id,
        "timestamp": timestamp,
        "schema_version": schema_version,
        "survey_data": survey_data,
    }
    data_hash = sha256_hex(json.dumps(canonical_for_hash, separators=(",", ":"), ensure_ascii=False))
    return {
        "local_id": local_id,
        "timestamp": timestamp,
        "schema_version": schema_version,
        "survey_data": survey_data,
        "data_hash": data_hash,
    }


def batch_hash(records: list[dict]) -> str:
    canonical_records = [
        {
            "local_id": r.get("local_id"),
            "timestamp": r.get("timestamp"),
            "schema_version": r.get("schema_version", 1),
            "survey_data": r.get("survey_data"),
            "data_hash": r.get("data_hash"),
        }
        for r in records
    ]
    canonical_json = json.dumps(canonical_records, separators=(",", ":"), ensure_ascii=False)
    return sha256_hex(canonical_json)


def sign_body(raw_body: bytes, signing_secret: str) -> tuple[str, str, str]:
    timestamp_raw = str(int(time.time()))
    nonce = uuid.uuid4().hex
    body_hash = hashlib.sha256(raw_body).digest()
    body_hash_b64 = base64.b64encode(body_hash).decode("ascii")
    message = f"{timestamp_raw}.{nonce}.{body_hash_b64}".encode("utf-8")
    signature = hmac.new(signing_secret.encode("utf-8"), message, hashlib.sha256).hexdigest().lower()
    return timestamp_raw, nonce, signature


def send_batch(base_url: str, api_key: str, user_id: str, signing_secret: str, records: list[dict], timeout: float) -> dict:
    payload = {
        "records": records,
        "batch_hash": batch_hash(records),
    }
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ts, nonce, sig = sign_body(raw, signing_secret)

    headers = {
        "Content-Type": "application/json",
        "X-API-Key": api_key,
        "X-User-Id": user_id,
        "X-Sync-Timestamp": ts,
        "X-Sync-Nonce": nonce,
        "X-Signature": sig,
        "X-Signature-Version": "1",
    }

    req = urllib.request.Request(f"{base_url}/save/batch", data=raw, headers=headers, method="POST")
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return {
                "status": resp.status,
                "latency_ms": (time.perf_counter() - started) * 1000.0,
                "body": body,
            }
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return {
            "status": exc.code,
            "latency_ms": (time.perf_counter() - started) * 1000.0,
            "body": body,
        }
    except Exception as exc:
        return {
            "status": 0,
            "latency_ms": (time.perf_counter() - started) * 1000.0,
            "body": str(exc),
        }


def fetch_metrics(base_url: str, api_key: str, timeout: float) -> dict:
    req = urllib.request.Request(f"{base_url}/sync/metrics", headers={"X-API-Key": api_key}, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def chunked(items: list[dict], chunk_size: int) -> list[list[dict]]:
    return [items[i:i + chunk_size] for i in range(0, len(items), chunk_size)]


def main() -> int:
    parser = argparse.ArgumentParser(description="Real-world batch sync load test")
    parser.add_argument("--base-url", default="http://127.0.0.1:5000")
    parser.add_argument("--records", type=int, default=500)
    parser.add_argument("--batch-size", type=int, default=50)
    parser.add_argument("--concurrency", type=int, default=4)
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument("--api-key", default=os.environ.get("API_KEY", "dev-key"))
    parser.add_argument("--user-id", default="reality-check-user")
    parser.add_argument("--signing-secret", default=os.environ.get("SYNC_SIGNING_SECRET", "dev-sync-signing-key"))
    args = parser.parse_args()

    all_records = [make_record(args.user_id, i) for i in range(args.records)]
    batches = chunked(all_records, max(1, min(50, args.batch_size)))

    print("=== Real-World Batch Sync Load ===")
    print(f"Base URL: {args.base_url}")
    print(f"Records: {args.records}")
    print(f"Batch size: {max(1, min(50, args.batch_size))}")
    print(f"Batch requests: {len(batches)}")

    statuses: dict[int, int] = {}
    failed_samples: list[dict] = []

    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as ex:
        futures = [
            ex.submit(
                send_batch,
                args.base_url,
                args.api_key,
                args.user_id,
                args.signing_secret,
                batch,
                args.timeout,
            )
            for batch in batches
        ]
        for fut in concurrent.futures.as_completed(futures):
            res = fut.result()
            statuses[res["status"]] = statuses.get(res["status"], 0) + 1
            if res["status"] >= 400 and len(failed_samples) < 5:
                failed_samples.append({"status": res["status"], "body": res["body"][:400]})

    elapsed = time.perf_counter() - started
    print("\n--- Summary ---")
    print(f"Total time: {elapsed:.2f}s")
    print(f"Status counts: {json.dumps(statuses, sort_keys=True)}")

    if failed_samples:
        print("\nSample failures:")
        for sample in failed_samples:
            print(f"- status={sample['status']} body={sample['body']}")

    try:
        metrics = fetch_metrics(args.base_url, args.api_key, args.timeout)
        print("\n--- /sync/metrics snapshot ---")
        print(json.dumps({
            "records_received": metrics.get("metrics", {}).get("records_received"),
            "records_synced": metrics.get("metrics", {}).get("records_synced"),
            "records_failed": metrics.get("metrics", {}).get("records_failed"),
            "backpressure_rejections": metrics.get("metrics", {}).get("backpressure_rejections", 0),
            "failure_reasons": metrics.get("metrics", {}).get("failure_reasons", {}),
        }, indent=2))
    except Exception as exc:
        print(f"Could not fetch /sync/metrics: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

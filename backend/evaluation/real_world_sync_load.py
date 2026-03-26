import argparse
import base64
import concurrent.futures
import hashlib
import hmac
import json
import os
import statistics
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def canonical_record_for_hash(local_id: str, timestamp: str, schema_version: int, survey_data: dict) -> dict:
    return {
        "local_id": local_id,
        "timestamp": timestamp,
        "schema_version": schema_version,
        "survey_data": survey_data,
    }


def sha256_hex(data: str) -> str:
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def build_payload(i: int, user_id: str) -> dict:
    local_id = f"rw-{user_id}-{i:05d}"
    timestamp = iso_now()
    schema_version = 1
    survey_data = {
        "source": "real_world_sync_load",
        "index": i,
        "symptom_score": i % 10,
        "pain_scale": (i % 5) + 1,
    }
    canonical = canonical_record_for_hash(local_id, timestamp, schema_version, survey_data)
    data_hash = sha256_hex(json.dumps(canonical, separators=(",", ":"), ensure_ascii=False))
    return {
        "local_id": local_id,
        "timestamp": timestamp,
        "schema_version": schema_version,
        "survey_data": survey_data,
        "data_hash": data_hash,
    }


def build_signature(raw_body: bytes, signing_secret: str, signature_version: str = "1") -> tuple[str, str, str]:
    timestamp_raw = str(int(time.time()))
    nonce = uuid.uuid4().hex
    body_hash = hashlib.sha256(raw_body).digest()
    body_hash_b64 = base64.b64encode(body_hash).decode("ascii")
    message = f"{timestamp_raw}.{nonce}.{body_hash_b64}".encode("utf-8")
    signature = hmac.new(signing_secret.encode("utf-8"), message, hashlib.sha256).hexdigest().lower()
    return timestamp_raw, nonce, signature


def send_one(base_url: str, api_key: str, user_id: str, signing_secret: str, i: int, timeout: float) -> dict:
    payload = build_payload(i, user_id)
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ts, nonce, sig = build_signature(raw, signing_secret)

    headers = {
        "Content-Type": "application/json",
        "X-API-Key": api_key,
        "X-User-Id": user_id,
        "X-Sync-Timestamp": ts,
        "X-Sync-Nonce": nonce,
        "X-Signature": sig,
        "X-Signature-Version": "1",
    }

    req = urllib.request.Request(f"{base_url}/save", data=raw, headers=headers, method="POST")
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            latency_ms = (time.perf_counter() - started) * 1000.0
            return {
                "ok": 200 <= resp.status < 300,
                "status": resp.status,
                "latency_ms": latency_ms,
                "body": body,
            }
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        latency_ms = (time.perf_counter() - started) * 1000.0
        return {
            "ok": False,
            "status": exc.code,
            "latency_ms": latency_ms,
            "body": body,
        }
    except Exception as exc:
        latency_ms = (time.perf_counter() - started) * 1000.0
        return {
            "ok": False,
            "status": 0,
            "latency_ms": latency_ms,
            "body": str(exc),
        }


def fetch_metrics(base_url: str, api_key: str, timeout: float) -> dict:
    req = urllib.request.Request(
        f"{base_url}/sync/metrics",
        headers={"X-API-Key": api_key},
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Run real-world sync load against /save endpoint")
    parser.add_argument("--base-url", default="http://127.0.0.1:5000")
    parser.add_argument("--writes", type=int, default=500)
    parser.add_argument("--concurrency", type=int, default=25)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--api-key", default=os.environ.get("API_KEY", "dev-key"))
    parser.add_argument("--user-id", default="reality-check-user")
    parser.add_argument("--signing-secret", default=os.environ.get("SYNC_SIGNING_SECRET", "dev-sync-signing-key"))
    args = parser.parse_args()

    print("=== Real-World Sync Load Test ===")
    print(f"Base URL: {args.base_url}")
    print(f"Writes: {args.writes}")
    print(f"Concurrency: {args.concurrency}")

    statuses: dict[int, int] = {}
    latencies: list[float] = []
    failed_samples: list[dict] = []

    started_all = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as ex:
        futures = [
            ex.submit(
                send_one,
                args.base_url,
                args.api_key,
                args.user_id,
                args.signing_secret,
                i,
                args.timeout,
            )
            for i in range(args.writes)
        ]

        for fut in concurrent.futures.as_completed(futures):
            res = fut.result()
            statuses[res["status"]] = statuses.get(res["status"], 0) + 1
            latencies.append(res["latency_ms"])
            if not res["ok"] and len(failed_samples) < 5:
                failed_samples.append({"status": res["status"], "body": res["body"][:300]})

    total_sec = time.perf_counter() - started_all
    p50 = statistics.median(latencies) if latencies else 0.0
    p95 = sorted(latencies)[int(0.95 * (len(latencies) - 1))] if latencies else 0.0

    print("\n--- Summary ---")
    print(f"Total time: {total_sec:.2f}s")
    print(f"Throughput: {args.writes / total_sec:.2f} req/s" if total_sec > 0 else "Throughput: n/a")
    print(f"Status counts: {json.dumps(statuses, sort_keys=True)}")
    print(f"Latency p50: {p50:.1f} ms")
    print(f"Latency p95: {p95:.1f} ms")

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
        print(f"\nCould not fetch /sync/metrics: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

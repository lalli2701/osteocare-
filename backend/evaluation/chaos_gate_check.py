import json
import os
import sys
from urllib import request, parse, error


BASE_URL = os.environ.get("SYNC_BASE_URL", "http://127.0.0.1:5000").rstrip("/")
API_KEY = os.environ.get("API_KEY", "dev-key")
MIN_SAMPLES = os.environ.get("SYNC_CHAOS_GATE_MIN_SAMPLES", "20")
MAX_SUCCESS_DROP = os.environ.get("SYNC_CHAOS_GATE_MAX_SUCCESS_DROP", "0.05")
MAX_LATENCY_INCREASE_RATIO = os.environ.get("SYNC_CHAOS_GATE_MAX_LATENCY_INCREASE_RATIO", "0.20")


def main() -> int:
    query = parse.urlencode(
        {
            "min_samples": MIN_SAMPLES,
            "max_success_drop": MAX_SUCCESS_DROP,
            "max_latency_increase_ratio": MAX_LATENCY_INCREASE_RATIO,
        }
    )
    url = f"{BASE_URL}/sync/chaos/gate?{query}"

    req = request.Request(
        url,
        method="GET",
        headers={
            "X-API-Key": API_KEY,
        },
    )

    try:
        with request.urlopen(req, timeout=20) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
            passed = bool(payload.get("passed"))
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            return 0 if passed else 1
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(body)
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            return 1
        except Exception:
            print(f"HTTP {exc.code}: {body}")
            return 1
    except Exception as exc:
        print(f"Chaos gate check failed: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

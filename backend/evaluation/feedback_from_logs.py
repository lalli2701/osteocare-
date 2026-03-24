from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent
LOG_PATH = BASE_DIR / "logs" / "chat_monitor.log"
SUMMARY_PATH = BASE_DIR / "evaluation" / "chat_monitor_summary.json"
CANDIDATES_PATH = BASE_DIR / "evaluation" / "knowledge_update_candidates.json"
EVAL_CANDIDATES_PATH = BASE_DIR / "evaluation" / "chatbot_eval_dataset_candidates.json"
REAL_GOLD_CANDIDATES_PATH = BASE_DIR / "evaluation" / "chatbot_eval_gold_from_logs_candidates.json"

MIN_QUERY_FREQ = 3
MAX_PER_CATEGORY = 20


def _categorize_query(query: str) -> str:
    q = query.lower()
    if any(word in q for word in ["bitcoin", "wifi", "coding", "movie", "football", "malware"]):
        return "adversarial"
    if any(word in q for word in [" and ", "both", "plus"]) and any(word in q for word in ["bone", "osteoporosis", "calcium"]):
        return "mixed_intent"
    if any(word in q for word in ["osteoperosis", "calcuim", "vitman", "excercise", "fraxture"]):
        return "typo"
    if len(q.split()) <= 3:
        return "vague"
    return "factual"


def _extract_json(line: str) -> dict | None:
    marker = "{"
    i = line.find(marker)
    if i < 0:
        return None
    payload = line[i:].strip()
    try:
        return json.loads(payload)
    except Exception:
        return None


def main() -> None:
    if not LOG_PATH.exists():
        summary = {
            "message": "chat_monitor.log not found",
            "log_path": str(LOG_PATH),
        }
        SUMMARY_PATH.write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(json.dumps(summary, indent=2))
        return

    lines = LOG_PATH.read_text(encoding="utf-8", errors="ignore").splitlines()
    events = [obj for obj in (_extract_json(line) for line in lines) if isinstance(obj, dict)]

    route_counts = Counter()
    confidence_counts = Counter()
    fallback_count = 0
    low_confidence_queries: Counter[str] = Counter()
    query_stats: dict[str, dict[str, int]] = {}

    for event in events:
        route = str(event.get("route", "unknown"))
        confidence = str(event.get("confidence", "unknown"))
        query = str(event.get("query", "")).strip().lower()
        fallback = bool(event.get("fallback_triggered", False))

        route_counts[route] += 1
        confidence_counts[confidence] += 1
        fallback_count += int(fallback)

        if confidence == "low" and query:
            low_confidence_queries[query] += 1

        if query:
            stats = query_stats.setdefault(
                query,
                {
                    "count": 0,
                    "low_conf": 0,
                    "domain_guard": 0,
                    "fallback": 0,
                    "valid_domain": 0,
                    "rag_like": 0,
                },
            )
            stats["count"] += 1
            stats["low_conf"] += int(confidence == "low")
            stats["domain_guard"] += int(route == "domain_guard")
            stats["fallback"] += int(fallback)
            stats["valid_domain"] += int(route != "domain_guard")
            stats["rag_like"] += int(route.startswith("rag"))

    total = len(events)
    fallback_rate = round((fallback_count / total) * 100, 2) if total else 0.0

    summary = {
        "total_events": total,
        "fallback_count": fallback_count,
        "fallback_rate": fallback_rate,
        "route_distribution": dict(route_counts),
        "confidence_distribution": dict(confidence_counts),
        "top_low_confidence_queries": [
            {"query": q, "count": c}
            for q, c in low_confidence_queries.most_common(30)
        ],
        "candidate_filtering": {
            "min_query_freq": MIN_QUERY_FREQ,
            "require_low_confidence": True,
            "exclude_domain_guard": True,
            "exclude_fallback_routes": True,
        },
    }

    filtered_candidates = []
    for query, stats in query_stats.items():
        if stats["count"] < MIN_QUERY_FREQ:
            continue
        if stats["low_conf"] == 0:
            continue
        if stats["domain_guard"] > 0:
            continue
        if stats["fallback"] > 0:
            continue

        filtered_candidates.append(
            {
                "query": query,
                "observed_count": stats["count"],
                "low_confidence_count": stats["low_conf"],
                "category": _categorize_query(query),
                "suggestion": "Consider adding a focused knowledge chunk or FAQ entry for this query.",
            }
        )

    filtered_candidates.sort(
        key=lambda item: (item["low_confidence_count"], item["observed_count"]),
        reverse=True,
    )

    # Balance candidate set so one user-distribution segment does not dominate updates.
    bucketed: dict[str, list[dict]] = {}
    for item in filtered_candidates:
        bucketed.setdefault(str(item.get("category", "factual")), []).append(item)

    balanced_candidates: list[dict] = []
    for category, items in bucketed.items():
        balanced_candidates.extend(items[:MAX_PER_CATEGORY])

    balanced_candidates.sort(
        key=lambda item: (item["low_confidence_count"], item["observed_count"]),
        reverse=True,
    )

    knowledge_candidates = {
        "generated_from": str(LOG_PATH),
        "candidates": balanced_candidates[:100],
    }

    eval_candidates = {
        "generated_from": str(LOG_PATH),
        "items": [
            {
                "query": item["query"],
                "category": str(item.get("category", "real_world")),
                "expected": "allow",
                "source": "logs_low_confidence_filtered",
            }
            for item in balanced_candidates[:150]
        ],
    }

    real_query_ranked = sorted(
        query_stats.items(),
        key=lambda kv: (int(kv[1].get("count", 0)), int(kv[1].get("rag_like", 0))),
        reverse=True,
    )
    real_gold_items = []
    for query, stats in real_query_ranked:
        if int(stats.get("count", 0)) < 1:
            continue
        if int(stats.get("domain_guard", 0)) >= max(1, int(stats.get("count", 0)) // 2):
            item = {
                "query": query,
                "expected_route": "domain_guard",
                "required_keywords": ["bone health"],
                "forbidden_keywords": [],
                "manual_verified": False,
                "source": "logs_real_queries",
                "observed_count": int(stats.get("count", 0)),
            }
        else:
            item = {
                "query": query,
                "expected_route_prefix": "rag",
                "required_keywords": [],
                "forbidden_keywords": [],
                "manual_verified": False,
                "source": "logs_real_queries",
                "observed_count": int(stats.get("count", 0)),
            }
        real_gold_items.append(item)
        if len(real_gold_items) >= 100:
            break

    real_gold_candidates = {
        "generated_from": str(LOG_PATH),
        "items": real_gold_items,
    }

    SUMMARY_PATH.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    CANDIDATES_PATH.write_text(json.dumps(knowledge_candidates, indent=2), encoding="utf-8")
    EVAL_CANDIDATES_PATH.write_text(json.dumps(eval_candidates, indent=2), encoding="utf-8")
    REAL_GOLD_CANDIDATES_PATH.write_text(json.dumps(real_gold_candidates, indent=2), encoding="utf-8")

    print(json.dumps({
        "summary": str(SUMMARY_PATH),
        "candidates": str(CANDIDATES_PATH),
        "eval_candidates": str(EVAL_CANDIDATES_PATH),
        "gold_candidates": str(REAL_GOLD_CANDIDATES_PATH),
        "total_events": total,
        "fallback_rate": fallback_rate,
    }, indent=2))


if __name__ == "__main__":
    main()

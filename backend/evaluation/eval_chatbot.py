from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from chatbot import chatbot_response

DATASET_PATH = BASE_DIR / "chatbot_eval_dataset.json"
OUTPUT_PATH = BASE_DIR / "chatbot_eval_report.json"
GOLD_DATASET_PATH = BASE_DIR / "chatbot_eval_gold_dataset.json"
NORMAL_CATEGORIES = {"factual", "vague", "mixed_intent", "typo", "multi_turn"}
NORMAL_CATEGORIES = NORMAL_CATEGORIES | {"long_tail", "multi_turn_drift", "mixed_language", "slang"}

RISK_TERMS = {"risk", "risks", "overdose", "side effect", "danger", "harm", "contraindication"}
BENEFIT_TERMS = {"benefit", "benefits", "improve", "strengthen", "prevention", "help"}
RECOVERY_TERMS = {"recovery", "recover", "after fracture", "post fracture", "rehab", "rehabilitation"}


def _build_extended_dataset(base_items: list[dict]) -> list[dict]:
    extended: list[dict] = [dict(item) for item in base_items]
    seen = {str(item.get("query", "")).strip().lower() for item in extended}

    def _add_item(item: dict) -> None:
        q = str(item.get("query", "")).strip()
        if not q:
            return
        key = q.lower()
        if key in seen:
            return
        seen.add(key)
        extended.append(item)

    allow_items = [i for i in base_items if str(i.get("expected", "")).strip().lower() in {"allow", "allow_focus"}]
    block_items = [i for i in base_items if str(i.get("expected", "")).strip().lower() == "block"]

    for item in allow_items[:80]:
        q = str(item.get("query", "")).strip()
        expected = str(item.get("expected", "allow")).strip().lower()
        _add_item({"query": f"{q} please give practical steps", "expected": expected, "category": "long_tail"})
        _add_item({"query": f"{q} in simple words", "expected": expected, "category": "slang"})

    typo_map = {
        "bone": "bon",
        "bones": "bons",
        "vitamin": "vitman",
        "exercise": "excercise",
        "fracture": "frakture",
        "osteoporosis": "osteoperosis",
    }
    for item in allow_items[:70]:
        q = str(item.get("query", "")).strip().lower()
        expected = str(item.get("expected", "allow")).strip().lower()
        q_typo = q
        replaced = False
        for src, dst in typo_map.items():
            if src in q_typo:
                q_typo = q_typo.replace(src, dst, 1)
                replaced = True
                break
        if replaced:
            _add_item({"query": q_typo, "expected": expected, "category": "long_tail"})

    for item in block_items[:35]:
        q = str(item.get("query", "")).strip()
        _add_item({"query": f"yo {q} asap", "expected": "block", "category": "slang"})

    mixed_language_items = [
        {"query": "bone pain ke liye practical diet tips", "expected": "allow", "category": "mixed_language"},
        {"query": "osteoporosis ki exercise videos suggest karo", "expected": "allow", "category": "mixed_language"},
        {"query": "fracture recovery ki meal planning cheppu", "expected": "allow", "category": "mixed_language"},
        {"query": "bone health app recommendations for reminders", "expected": "allow", "category": "long_tail"},
        {"query": "best apps for bone health tracking", "expected": "allow", "category": "long_tail"},
        {"query": "exercise videos for bones beginners", "expected": "allow", "category": "long_tail"},
    ]
    for item in mixed_language_items:
        _add_item(item)

    multi_turn_drift_items = [
        {
            "query": "what about calcium timing now",
            "history": [
                {"role": "user", "content": "i have osteopenia"},
                {"role": "assistant", "content": "lifestyle steps can reduce progression risk."},
                {"role": "user", "content": "what daily plan should i start"},
            ],
            "expected": "allow",
            "category": "multi_turn_drift",
        },
        {
            "query": "and safe exercises after fracture",
            "history": [
                {"role": "user", "content": "my mother had a wrist fracture"},
                {"role": "assistant", "content": "recovery should include guided rehabilitation."},
                {"role": "user", "content": "how long recovery can take"},
            ],
            "expected": "allow",
            "category": "multi_turn_drift",
        },
        {
            "query": "what diet changes then",
            "history": [
                {"role": "user", "content": "post menopause bone loss risk"},
                {"role": "assistant", "content": "risk rises after menopause and needs prevention."},
                {"role": "user", "content": "what screening do i need"},
            ],
            "expected": "allow",
            "category": "multi_turn_drift",
        },
    ]
    for item in multi_turn_drift_items:
        _add_item(item)

    return extended


def _keyword_coverage(answer: str, required_keywords: list[str]) -> float:
    if not required_keywords:
        return 1.0
    answer_l = answer.lower()
    hit = sum(1 for kw in required_keywords if kw and kw.lower() in answer_l)
    return hit / max(1, len(required_keywords))


def _directionality_score(query: str, answer: str) -> tuple[float, bool]:
    q = query.lower()
    a = answer.lower()

    q_has_risk = any(term in q for term in RISK_TERMS)
    q_has_recovery = any(term in q for term in RECOVERY_TERMS)
    a_has_risk = any(term in a for term in RISK_TERMS)
    a_has_benefit = any(term in a for term in BENEFIT_TERMS)
    a_has_recovery = any(term in a for term in RECOVERY_TERMS)

    if q_has_risk:
        if a_has_risk:
            return 1.0, False
        if a_has_benefit and not a_has_risk:
            return 0.2, True
        return 0.4, True

    if q_has_recovery:
        if a_has_recovery:
            return 1.0, False
        return 0.3, True

    return 0.8, False


def _correctness_score(
    query: str,
    answer: str,
    expected: str,
    blocked: bool,
    required_keywords: list[str],
    forbidden_keywords: list[str],
) -> tuple[float, bool, bool]:
    if expected == "block":
        return (1.0 if blocked else 0.0), False, not blocked

    if blocked:
        return 0.0, False, True

    answer_l = answer.lower()
    coverage = _keyword_coverage(answer, required_keywords)
    forbidden_violation = any(kw.lower() in answer_l for kw in forbidden_keywords if kw)
    direction_score, direction_miss = _directionality_score(query, answer)

    score = (0.55 * coverage) + (0.45 * direction_score)
    if forbidden_violation:
        score = max(0.0, score - 0.5)

    partial_failure = (0.0 < score < 0.75) or direction_miss or forbidden_violation
    hard_failure = score < 0.25 or forbidden_violation
    return round(max(0.0, min(1.0, score)), 3), partial_failure, hard_failure


def _relevance_score(expected: str, blocked: bool, focused: bool, route: str) -> float:
    if expected == "block":
        return 1.0 if blocked else 0.0
    if expected == "allow":
        return 0.0 if blocked else 1.0
    if expected == "allow_focus":
        if blocked:
            return 0.0
        if focused:
            return 1.0
        if "rag" in route:
            return 0.8
        return 0.6
    return 0.5


def _grounding_score(route: str, confidence: str, context_count: int) -> float:
    route_l = route.lower()
    conf = str(confidence).lower()

    if route_l == "domain_guard":
        return 1.0
    if route_l.startswith("faq"):
        return 0.95
    if "rag" in route_l:
        base = 0.55 + min(context_count, 3) * 0.1
        if conf == "high":
            base += 0.15
        elif conf == "medium":
            base += 0.08
        return min(base, 1.0)
    if "fallback_general" in route_l:
        return 0.55
    if "fallback_faq" in route_l:
        return 0.8
    if "fallback_static" in route_l:
        return 0.35
    return 0.5


def _usefulness_score(
    expected: str,
    route: str,
    answer: str,
    blocked: bool,
    context_count: int,
) -> float:
    route_l = route.lower()
    answer_l = answer.lower().strip()

    if expected == "block":
        return 1.0 if blocked else 0.0

    if blocked:
        return 0.0

    base = 0.45
    # Penalize fallback first, even when route string contains rag_* prefixes.
    if "fallback_static" in route_l:
        base -= 0.28
    elif "fallback_general" in route_l:
        base -= 0.12
    elif "fallback_faq" in route_l:
        base += 0.02
    elif "rag_strong" in route_l:
        base += 0.35
    elif "rag_weak" in route_l:
        base += 0.22
    elif "faq" in route_l:
        base += 0.2

    if context_count >= 2:
        base += 0.12
    elif context_count == 1:
        base += 0.06

    if len(answer_l) < 40:
        base -= 0.1
    elif len(answer_l) > 140:
        base += 0.08

    if "i can help" in answer_l and "please try again" in answer_l:
        base -= 0.25

    return round(max(0.0, min(1.0, base)), 3)


def evaluate_item(item: dict) -> dict:
    query = str(item.get("query", "")).strip()
    expected = str(item.get("expected", "")).strip().lower()
    category = str(item.get("category", "unknown")).strip().lower()
    history = item.get("history")
    if not isinstance(history, list):
        history = None
    required_keywords = [str(k).strip().lower() for k in item.get("required_keywords", []) if str(k).strip()]
    forbidden_keywords = [str(k).strip().lower() for k in item.get("forbidden_keywords", []) if str(k).strip()]

    start = time.perf_counter()
    result = chatbot_response(query, history=history, return_meta=True)
    latency_ms = (time.perf_counter() - start) * 1000.0
    if not isinstance(result, dict):
        result = {
            "answer": str(result),
            "route": "legacy",
            "confidence": "low",
            "best_distance": None,
            "gap": None,
            "context_count": 0,
        }

    route = str(result.get("route", "unknown"))
    answer = str(result.get("answer", ""))
    confidence = str(result.get("confidence", "low"))
    context_count = int(result.get("context_count") or 0)

    blocked = route == "domain_guard"
    focused = answer.lower().startswith("i will focus only on the bone-health part")
    fallback_triggered = "fallback" in route
    correctness_score, partial_failure, hard_failure = _correctness_score(
        query,
        answer,
        expected,
        blocked,
        required_keywords,
        forbidden_keywords,
    )

    if expected == "block":
        passed = blocked
    elif expected == "allow":
        passed = not blocked
    elif expected == "allow_focus":
        passed = (not blocked) and (focused or "rag" in route or "fallback" in route)
    else:
        passed = True

    return {
        "query": query,
        "category": category,
        "expected": expected,
        "passed": passed,
        "route": route,
        "confidence": confidence,
        "best_distance": result.get("best_distance"),
        "gap": result.get("gap"),
        "context_count": context_count,
        "latency_ms": round(latency_ms, 2),
        "fallback_triggered": fallback_triggered,
        "relevance_score": round(_relevance_score(expected, blocked, focused, route), 3),
        "grounding_score": round(_grounding_score(route, confidence, context_count), 3),
        "usefulness_score": _usefulness_score(expected, route, answer, blocked, context_count),
        "correctness_score": correctness_score,
        "partial_failure": partial_failure,
        "hard_failure": hard_failure,
        "history_used": bool(history),
    }


def evaluate_gold_item(item: dict) -> dict:
    query = str(item.get("query", "")).strip()
    expected_route = str(item.get("expected_route", "")).strip()
    expected_route_prefix = str(item.get("expected_route_prefix", "")).strip()
    required_keywords = [str(k).lower() for k in item.get("required_keywords", []) if str(k).strip()]
    forbidden_keywords = [str(k).lower() for k in item.get("forbidden_keywords", []) if str(k).strip()]

    start = time.perf_counter()
    result = chatbot_response(query, return_meta=True)
    latency_ms = (time.perf_counter() - start) * 1000.0

    if not isinstance(result, dict):
        result = {
            "answer": str(result),
            "route": "legacy",
            "confidence": "low",
            "context_count": 0,
            "gap": None,
            "best_distance": None,
        }

    route = str(result.get("route", "unknown"))
    answer_text = str(result.get("answer", ""))
    answer = answer_text.lower()

    route_pass = True
    if expected_route:
        route_pass = route == expected_route
    elif expected_route_prefix:
        route_pass = route.startswith(expected_route_prefix)

    required_pass = all(k in answer for k in required_keywords) if required_keywords else True
    forbidden_pass = all(k not in answer for k in forbidden_keywords) if forbidden_keywords else True

    passed = route_pass and required_pass and forbidden_pass
    coverage = _keyword_coverage(answer_text, required_keywords)
    grounding_score = round(coverage if forbidden_pass else 0.0, 3)
    relevance_score = 1.0 if route_pass else 0.0
    blocked = route == "domain_guard"
    usefulness_score = _usefulness_score("allow", route, answer_text, blocked, int(result.get("context_count") or 0))

    correctness_score = (0.6 * (1.0 if route_pass else 0.0)) + (0.3 * coverage) + (0.1 * (1.0 if forbidden_pass else 0.0))
    if not forbidden_pass:
        correctness_score = max(0.0, correctness_score - 0.5)
    correctness_score = round(max(0.0, min(1.0, correctness_score)), 3)
    partial_failure = (0.0 < correctness_score < 0.75) or (not required_pass)
    hard_failure = correctness_score < 0.25 or (not forbidden_pass)

    return {
        "query": query,
        "category": "gold",
        "expected_route": expected_route,
        "expected_route_prefix": expected_route_prefix,
        "passed": passed,
        "route_pass": route_pass,
        "required_keywords_pass": required_pass,
        "forbidden_keywords_pass": forbidden_pass,
        "route": route,
        "confidence": result.get("confidence"),
        "best_distance": result.get("best_distance"),
        "gap": result.get("gap"),
        "context_count": result.get("context_count"),
        "latency_ms": round(latency_ms, 2),
        "fallback_triggered": "fallback" in route,
        "relevance_score": relevance_score,
        "grounding_score": grounding_score,
        "usefulness_score": usefulness_score,
        "correctness_score": correctness_score,
        "partial_failure": partial_failure,
        "hard_failure": hard_failure,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate chatbot routes and guard behavior.")
    parser.add_argument("--limit", type=int, default=0, help="Evaluate only the first N items (0 = all).")
    parser.add_argument(
        "--dataset",
        choices=["default", "gold", "extended"],
        default="default",
        help="Run default synthetic set, gold reviewed set, or extended long-tail set.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        help="Number of parallel workers for evaluation (default: 1).",
    )
    args = parser.parse_args()

    if args.dataset == "gold":
        dataset_path = GOLD_DATASET_PATH
        items = json.loads(dataset_path.read_text(encoding="utf-8"))
    elif args.dataset == "extended":
        dataset_path = Path("generated://extended")
        base_items = json.loads(DATASET_PATH.read_text(encoding="utf-8"))
        items = _build_extended_dataset(base_items)
    else:
        dataset_path = DATASET_PATH
        items = json.loads(dataset_path.read_text(encoding="utf-8"))
    if args.limit and args.limit > 0:
        items = items[: args.limit]

    evaluator = evaluate_gold_item if args.dataset == "gold" else evaluate_item
    workers = max(1, int(args.workers))
    if workers == 1:
        rows = [evaluator(item) for item in items]
    else:
        with ThreadPoolExecutor(max_workers=workers) as executor:
            rows = list(executor.map(evaluator, items))

    total = len(rows)
    passed = sum(1 for row in rows if row["passed"])

    by_category = defaultdict(lambda: {"total": 0, "passed": 0})
    route_counts = Counter()
    confidence_counts = Counter()
    fallback_count = 0
    normal_total = 0
    normal_fallback = 0
    latency_values: list[float] = []
    relevance_scores: list[float] = []
    grounding_scores: list[float] = []
    usefulness_scores: list[float] = []
    correctness_scores: list[float] = []
    partial_failure_count = 0
    hard_failure_count = 0

    for row in rows:
        cat = row["category"]
        by_category[cat]["total"] += 1
        by_category[cat]["passed"] += int(bool(row["passed"]))
        route_counts[row["route"]] += 1
        confidence_counts[str(row["confidence"])] += 1
        fallback_count += int(bool(row.get("fallback_triggered", False)))
        if cat in NORMAL_CATEGORIES:
            normal_total += 1
            normal_fallback += int(bool(row.get("fallback_triggered", False)))
        latency_values.append(float(row.get("latency_ms", 0.0)))
        relevance_scores.append(float(row.get("relevance_score", 0.0)))
        grounding_scores.append(float(row.get("grounding_score", 0.0)))
        usefulness_scores.append(float(row.get("usefulness_score", 0.0)))
        correctness_scores.append(float(row.get("correctness_score", 0.0)))
        partial_failure_count += int(bool(row.get("partial_failure", False)))
        hard_failure_count += int(bool(row.get("hard_failure", False)))

    latency_sorted = sorted(latency_values)
    if latency_sorted:
        idx = int(round(0.95 * (len(latency_sorted) - 1)))
        p95_latency = latency_sorted[idx]
    else:
        p95_latency = 0.0

    # Detailed fallback analysis
    rag_strong_rows = [r for r in rows if r["route"].startswith("rag_strong")]
    rag_strong_fallback = [r for r in rag_strong_rows if "fallback" in r["route"]]
    rag_strong_fallback_rate = (
        round((len(rag_strong_fallback) / len(rag_strong_rows)) * 100, 2)
        if rag_strong_rows
        else 0.0
    )

    report = {
        "dataset": str(dataset_path),
        "total": total,
        "passed": passed,
        "pass_rate": round((passed / total) * 100, 2) if total else 0.0,
        "by_category": {
            cat: {
                "total": stats["total"],
                "passed": stats["passed"],
                "pass_rate": round((stats["passed"] / stats["total"]) * 100, 2)
                if stats["total"]
                else 0.0,
            }
            for cat, stats in by_category.items()
        },
        "route_distribution": dict(route_counts),
        "confidence_distribution": dict(confidence_counts),
        "fallback_rate": round((fallback_count / total) * 100, 2) if total else 0.0,
        "fallback_rate_normal_queries": round((normal_fallback / normal_total) * 100, 2) if normal_total else 0.0,
        "normal_query_total": normal_total,
        "normal_query_fallback_count": normal_fallback,
        "rag_strong_queries": len(rag_strong_rows),
        "rag_strong_fallback_rate_pct": rag_strong_fallback_rate,
        "rag_strong_fallback_queries": rag_strong_fallback,
        "latency_ms_avg": round(sum(latency_values) / len(latency_values), 2) if latency_values else 0.0,
        "latency_ms_p95": round(p95_latency, 2),
        "grounding_score_avg": round(sum(grounding_scores) / len(grounding_scores), 3) if grounding_scores else 0.0,
        "relevance_score_avg": round(sum(relevance_scores) / len(relevance_scores), 3) if relevance_scores else 0.0,
        "usefulness_score_avg": round(sum(usefulness_scores) / len(usefulness_scores), 3) if usefulness_scores else 0.0,
        "correctness_score_avg": round(sum(correctness_scores) / len(correctness_scores), 3) if correctness_scores else 0.0,
        "partial_failure_count": partial_failure_count,
        "hard_failure_count": hard_failure_count,
        "failures": [row for row in rows if not row["passed"]],
    }

    OUTPUT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({
        "dataset": str(dataset_path),
        "total": report["total"],
        "passed": report["passed"],
        "pass_rate": report["pass_rate"],
        "workers": workers,
        "output": str(OUTPUT_PATH),
    }, indent=2))


if __name__ == "__main__":
    main()

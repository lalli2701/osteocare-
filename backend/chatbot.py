from __future__ import annotations

import math
import os
import re
import time
from collections import OrderedDict
from typing import Any

from llm import (
    answer_supported_by_context,
    generate_rag_answer,
    generate_general_answer,
    is_llm_unavailable_response,
    rewrite_query_for_retrieval,
)
from knowledge import KNOWLEDGE_VERSION, get_knowledge_version
from retriever import hybrid_retrieve, keyword_search, rerank_hybrid_candidates, retrieve_with_scores
from retriever import fast_rank_hybrid_candidates


# Greeting patterns for basic intent classification
GREETINGS = {"hi", "hello", "hey", "good morning", "good afternoon", "good evening", "greetings"}
THANKS = {"thanks", "thank you", "thankyou", "appreciate it", "cheers"}
SMALL_TALK = GREETINGS | THANKS | {"how are you", "what's up", "sup"}

FAQ_RULES = [
    (
        ("what is osteoporosis", "osteoporosis disease", "explain osteoporosis"),
        "Osteoporosis is a condition where bones become weak and fragile, "
        "which increases the risk of fractures. This is educational information "
        "and not a medical diagnosis.",
    ),
    (
        ("what is calcium", "explain calcium"),
        "Calcium is a mineral your body needs to build and maintain strong bones "
        "and teeth. You can get it from foods like milk, curd, paneer, leafy greens, "
        "and fortified foods. This is educational information and not medical advice.",
    ),
    (
        ("what is bmi", "explain bmi"),
        "BMI stands for Body Mass Index, a screening measure based on height and weight. "
        "It is useful for population-level risk checks but does not diagnose disease. "
        "This is educational information and not a medical diagnosis.",
    ),
]

BONE_CORE_KEYWORDS = {
    "bone", "bones", "osteoporosis", "fracture", "calcium", "vitamin d", "dexa", "bmd",
    "osteopenia", "hip", "spine", "postmenopause", "menopause", "steroid",
    "bisphosphonate", "bisphosphonates",
    "bon", "bons", "osteoperosis", "frakture", "fraktures", "vitman",
}

HEALTH_SUPPORT_KEYWORDS = {
    "exercise", "exercises", "walk", "walking", "diet", "food", "foods", "eat",
    "nutrition", "vitamin", "meal", "meals",
    "arthritis", "fall", "falls", "smoking", "alcohol", "risk", "doctor", "health", "bmi",
}

OFF_TOPIC_KEYWORDS = {
    "coding", "programming", "wifi", "bitcoin", "crypto", "stock", "javascript", "python",
    "movie", "joke", "football", "cricket", "energy drink", "gpu", "cpu",
    "seo", "instagram", "react", "mobile app", "app development",
}

OFF_TOPIC_STRICT_TERMS = {
    "hack", "hacking", "exploit", "malware", "virus", "ransomware", "phishing",
    "sql injection", "xss", "ddos", "bomb", "weapon", "porn", "sex",
}

BONE_UTILITY_TERMS = {
    "app", "apps", "video", "videos", "tracker", "tracking", "reminder", "youtube",
}

FOLLOWUP_HINT_STOPWORDS = {
    "what", "about", "this", "that", "it", "and", "for", "with", "from", "how", "why",
    "is", "are", "the", "a", "an", "to", "of", "in", "on", "my", "your", "their",
}

PRACTICAL_QUERY_TERMS = {
    "how to", "plan", "routine", "examples", "example", "sample", "what should i do",
    "what to do next", "diet", "exercise", "workout", "meal", "meals", "weekly",
}

STRONG_MATCH_MAX = 1.2
WEAK_MATCH_MAX = 1.8
GUARD_MAX = 1.9
STRONG_GAP_MIN = 0.3
VECTOR_TOP_K = 5
SPARSE_TOP_K = 5
RERANK_TOP_K = 3
RERANK_SKIP_DISTANCE_MAX = float(os.getenv("RERANK_SKIP_DISTANCE_MAX", "0.8"))
RERANK_SKIP_GAP_MIN = float(os.getenv("RERANK_SKIP_GAP_MIN", "0.3"))
RERANK_EARLY_EXIT_MIN_BUDGET_SEC = float(os.getenv("RERANK_EARLY_EXIT_MIN_BUDGET_SEC", "2.0"))
RERANK_PARTIAL_MAX_BUDGET_SEC = float(os.getenv("RERANK_PARTIAL_MAX_BUDGET_SEC", "5.0"))
RERANK_PARTIAL_TOP_K = int(os.getenv("RERANK_PARTIAL_TOP_K", "2"))
RERANK_MAX_TIME_SEC = float(os.getenv("RERANK_MAX_TIME_SEC", "1.5"))
RERANK_EARLY_STOP_SCORE = float(os.getenv("RERANK_EARLY_STOP_SCORE", "8.0"))
CONSISTENCY_TTL_SEC = 600
CONSISTENCY_CACHE_MAX = 256
REQUEST_BUDGET_SEC = 12.0
MAX_RESPONSE_TIME_SEC = float(os.getenv("CHAT_TOTAL_BUDGET_SEC", "5"))
SELF_CHECK_SKIP_CONFIDENCE = float(os.getenv("SELF_CHECK_SKIP_CONFIDENCE", "0.8"))
MIN_SELF_CHECK_TIMEOUT_SEC = 1.0
_CONSISTENCY_CACHE: OrderedDict[str, tuple[float, str, str, str]] = OrderedDict()
_CACHE_KNOWLEDGE_VERSION = KNOWLEDGE_VERSION
REWRITE_TTL_SEC = 1800
REWRITE_CACHE_MAX = 512
_REWRITE_CACHE: OrderedDict[str, tuple[float, str, str]] = OrderedDict()

# Monitor fallback behavior for production observability
_FALLBACK_STATS = {
    "total_queries": 0,
    "fallback_queries": 0,
    "rag_strong_fallback": 0,
    "rag_weak_fallback": 0,
    "guard_fallback": 0,
    "no_retrieval_fallback": 0,
}

STRICT_MEDICAL_TERMS = {
    "dose", "dosage", "treatment", "drug", "medicine", "medication", "prescription",
    "diagnosis", "diagnose", "symptoms", "side effect", "contraindication", "fracture",
    "bisphosphonate", "bisphosphonates",
}

RISK_INTENT_TERMS = {"risk", "risks", "overdose", "danger", "harm", "side effect", "contraindication"}
CAUSE_INTENT_TERMS = {"cause", "causes", "why", "reason", "reasons"}
PREVENTION_INTENT_TERMS = {"prevent", "prevention", "avoid", "reduce", "protect"}
TREATMENT_INTENT_TERMS = {"treat", "treatment", "manage", "management", "medicine", "medication", "therapy"}
RECOVERY_INTENT_TERMS = {"recovery", "recover", "after fracture", "post fracture", "rehab", "rehabilitation"}

AMBIGUOUS_REFERENCE_TERMS = {
    "it", "this", "that", "they", "them", "those", "these", "its", "their",
}


def _clean_query(query: str) -> str:
    q = query.lower().strip()
    q = re.sub(r"[^a-z0-9\s]", " ", q)
    q = re.sub(r"\s+", " ", q).strip()
    return q


def _contains_term(query: str, term: str) -> bool:
    return re.search(rf"\b{re.escape(term)}\b", query) is not None


def _keyword_overlap_score(query: str, text: str) -> int:
    query_tokens = set(_clean_query(query).split())
    text_tokens = set(_clean_query(text).split())
    return len(query_tokens & text_tokens)


def _compute_confidence(best_distance: float, gap: float, context_count: int) -> str:
    score = _compute_confidence_score(best_distance, gap, context_count)
    if score >= 0.65:
        return "high"
    if score >= 0.40:
        return "medium"
    return "low"


def _compute_confidence_score(best_distance: float, gap: float, context_count: int) -> float:
    score = 0.0

    if best_distance < 1.1:
        score += 0.45
    elif best_distance < 1.4:
        score += 0.30
    elif best_distance < 1.8:
        score += 0.18
    elif best_distance < 2.1:
        score += 0.08

    if gap > 0.35:
        score += 0.25
    elif gap > 0.20:
        score += 0.15
    elif gap > 0.10:
        score += 0.08

    if context_count >= 3:
        score += 0.20
    elif context_count == 2:
        score += 0.14
    elif context_count == 1:
        score += 0.08

    return score


def _history_cache_fingerprint(history: list[dict[str, str]] | None) -> str:
    if not history:
        return "none"

    parts: list[str] = []
    for item in history[-4:]:
        role = str(item.get("role", "")).strip().lower()
        content = str(item.get("content", "")).strip().lower()
        if role in {"user", "assistant"} and content:
            parts.append(f"{role}:{content[:60]}")
    return "|".join(parts) if parts else "none"


def _ensure_cache_fresh() -> None:
    global _CACHE_KNOWLEDGE_VERSION
    latest_version = get_knowledge_version()
    if latest_version != _CACHE_KNOWLEDGE_VERSION:
        _CONSISTENCY_CACHE.clear()
        _REWRITE_CACHE.clear()
        _CACHE_KNOWLEDGE_VERSION = latest_version


def _build_cache_key(canonical_query: str, history: list[dict[str, str]] | None) -> str:
    core_hits, support_hits, off_topic_hits = _intent_profile(canonical_query)
    history_fp = _history_cache_fingerprint(history)
    return (
        f"v={_CACHE_KNOWLEDGE_VERSION};q={canonical_query};"
        f"i={core_hits}:{support_hits}:{off_topic_hits};h={history_fp}"
    )


def _consistency_cache_get(cache_key: str) -> tuple[str, str, str] | None:
    now = time.time()
    item = _CONSISTENCY_CACHE.get(cache_key)
    if item is None:
        return None

    ts, answer, route, confidence = item
    if now - ts > CONSISTENCY_TTL_SEC:
        _CONSISTENCY_CACHE.pop(cache_key, None)
        return None

    _CONSISTENCY_CACHE.move_to_end(cache_key)
    return answer, route, confidence


def _consistency_cache_set(cache_key: str, answer: str, route: str, confidence: str) -> None:
    # Cache only stable, high-confidence answers to reduce stale/error amplification.
    if confidence != "high":
        return
    if "fallback" in route or route == "domain_guard":
        return

    _CONSISTENCY_CACHE[cache_key] = (time.time(), answer, route, confidence)
    _CONSISTENCY_CACHE.move_to_end(cache_key)
    while len(_CONSISTENCY_CACHE) > CONSISTENCY_CACHE_MAX:
        _CONSISTENCY_CACHE.popitem(last=False)


def _rewrite_cache_get(key: str) -> tuple[str, str] | None:
    now = time.time()
    item = _REWRITE_CACHE.get(key)
    if item is None:
        return None
    ts, value, confidence = item
    if now - ts > REWRITE_TTL_SEC:
        _REWRITE_CACHE.pop(key, None)
        return None
    _REWRITE_CACHE.move_to_end(key)
    return value, confidence


def _rewrite_cache_set(key: str, value: str, confidence: str) -> None:
    _REWRITE_CACHE[key] = (time.time(), value, confidence)
    _REWRITE_CACHE.move_to_end(key)
    while len(_REWRITE_CACHE) > REWRITE_CACHE_MAX:
        _REWRITE_CACHE.popitem(last=False)


def _rewrite_query_cached(cleaned_query: str, history: list[dict[str, str]] | None) -> tuple[str, str]:
    key = f"{cleaned_query}|{_history_cache_fingerprint(history)}"
    hit = _rewrite_cache_get(key)
    if hit is not None:
        return hit

    rewritten, confidence = rewrite_query_for_retrieval(cleaned_query, history=history)
    rewritten_clean = _clean_query(rewritten)
    if not rewritten_clean:
        rewritten_clean = cleaned_query
        confidence = "low"

    _rewrite_cache_set(key, rewritten_clean, confidence)
    return rewritten_clean, confidence


def _self_check_mode(query: str) -> str:
    q = _clean_query(query)
    if any(_contains_term(q, term) for term in STRICT_MEDICAL_TERMS):
        return "strict"
    return "relaxed"


def _within_budget(started_at: float) -> bool:
    return (time.perf_counter() - started_at) <= REQUEST_BUDGET_SEC


def _remaining_total_budget(started_at: float) -> float:
    return max(0.0, MAX_RESPONSE_TIME_SEC - (time.perf_counter() - started_at))


def _fast_timeout_fallback() -> tuple[str, str]:
    return (
        "I can help with bone health basics like osteoporosis prevention, exercise, diet, and fall safety. "
        "Please try again shortly for a detailed response.",
        "fallback_static_timeout",
    )


def _dynamic_rerank_top_k(gap: float) -> int:
    """Set rerank breadth from uncertainty: lower gap => higher ambiguity."""
    if gap < 0.2:
        return 3
    if gap < 0.35:
        return 2
    return 1


def _should_skip_rewrite(cleaned_query: str, history: list[dict[str, str]] | None) -> bool:
    """Skip rewrite for short, direct queries to avoid unnecessary LLM calls."""
    tokens = cleaned_query.split()
    if not tokens:
        return True

    if history:
        # Keep rewrite enabled for multi-turn queries where pronoun resolution may help retrieval.
        return False

    if len(tokens) <= 4 and not any(tok in AMBIGUOUS_REFERENCE_TERMS for tok in tokens):
        return True

    return False


def _intent_profile(query: str) -> tuple[int, int, int]:
    q = _clean_query(query)
    core_hits = sum(1 for term in BONE_CORE_KEYWORDS if _contains_term(q, term))
    support_hits = sum(1 for term in HEALTH_SUPPORT_KEYWORDS if _contains_term(q, term))
    off_topic_hits = sum(1 for term in OFF_TOPIC_KEYWORDS if _contains_term(q, term))
    return core_hits, support_hits, off_topic_hits


def _effective_off_topic_hits(query: str, core_hits: int, support_hits: int, off_topic_hits: int) -> int:
    q = _clean_query(query)
    utility_hits = sum(1 for term in BONE_UTILITY_TERMS if _contains_term(q, term))
    if (core_hits > 0 or support_hits > 0) and utility_hits > 0:
        return max(0, off_topic_hits - 1)
    return off_topic_hits


def _history_topic_hint(history: list[dict[str, str]] | None) -> str:
    if not history:
        return ""

    tokens: list[str] = []
    for item in history[-6:]:
        role = str(item.get("role", "")).strip().lower()
        if role != "user":
            continue
        content = _clean_query(str(item.get("content", "")))
        for tok in content.split():
            if len(tok) < 4:
                continue
            if tok in FOLLOWUP_HINT_STOPWORDS:
                continue
            if tok in OFF_TOPIC_KEYWORDS:
                continue
            if tok in BONE_CORE_KEYWORDS or tok in HEALTH_SUPPORT_KEYWORDS or tok in STRICT_MEDICAL_TERMS:
                tokens.append(tok)

    if not tokens:
        return ""

    dedup: list[str] = []
    for tok in reversed(tokens):
        if tok not in dedup:
            dedup.append(tok)
        if len(dedup) >= 3:
            break
    dedup.reverse()
    return " ".join(dedup)


def _strict_medical_hits(query: str) -> int:
    q = _clean_query(query)
    return sum(1 for term in STRICT_MEDICAL_TERMS if _contains_term(q, term))


def _is_practical_query(query: str) -> bool:
    q = _clean_query(query)
    return any(term in q for term in PRACTICAL_QUERY_TERMS)


def _profile_hint(query: str, history: list[dict[str, str]] | None = None) -> str:
    q = _clean_query(query)
    if history:
        for item in history[-6:]:
            if str(item.get("role", "")).strip().lower() == "user":
                q += " " + _clean_query(str(item.get("content", "")))

    hints: list[str] = []
    if any(term in q for term in {"elderly", "senior", "older", "old age", "above 60", "age 60", "age 65"}):
        hints.append("older adult profile")
    if any(term in q for term in {"postmenopause", "menopause", "woman", "women", "female"}):
        hints.append("female/post-menopause risk profile")
    elif any(term in q for term in {"male", "man", "men"}):
        hints.append("male risk profile")

    return "; ".join(hints)


def _interpretation_response(query: str) -> tuple[str, str] | None:
    raw = str(query).strip().lower()
    q = _clean_query(query)

    tscore_match = re.search(r"(?:t[^a-z0-9]{0,3}score|tscore)[^0-9\-]{0,8}(-?\d+(?:[\.,]\d+)?)", raw)
    if tscore_match:
        try:
            score = float(str(tscore_match.group(1)).replace(",", "."))
        except Exception:
            score = None
        if score is not None:
            if score <= -2.5:
                severity = "This is in the osteoporosis range (higher fracture risk)."
            elif score < -1.0:
                severity = "This is in the osteopenia range (early bone loss risk)."
            else:
                severity = "This is in the normal/near-normal range for bone density."

            answer = (
                f"Your T-score is {score:.1f}. {severity}\n"
                "What this means in practice:\n"
                "- Risk level should be interpreted with age, fracture history, and other risk factors.\n"
                "- Prevention still matters: calcium/vitamin D adequacy, weight-bearing activity, and fall prevention.\n"
                "- If score is low, discuss formal fracture-risk assessment and treatment options with your doctor.\n"
                "What to do next: take this report to a clinician and review a personalized bone-health plan."
            )
            return answer, "interpret_tscore"

    if "calcium" in q and ("mg" in raw or "milligram" in raw):
        mg_match = re.search(r"\b(\d{2,4})\s*mg\b", raw)
        if mg_match:
            mg = int(mg_match.group(1))
            target = 1200 if any(term in q for term in {"postmenopause", "menopause", "older", "elderly", "female"}) else 1000
            if mg < 800:
                status = "likely low for most adults"
            elif mg < target:
                status = "close, but may be below common daily targets"
            elif mg <= 1300:
                status = "generally within common daily target range"
            else:
                status = "possibly high depending on total diet + supplements"

            answer = (
                f"Calcium intake of {mg} mg/day is {status}.\n"
                f"Typical target is around {target} mg/day (individual needs vary).\n"
                "Practical examples to reach target:\n"
                "- Include 2-3 calcium-rich servings daily (for example milk/curd/yogurt, paneer, fortified foods, leafy greens).\n"
                "- Pair calcium intake with vitamin D and regular weight-bearing activity.\n"
                "- Avoid very high supplementation without medical guidance.\n"
                "What to do next: review your full diet + supplement total with your doctor, especially if you have kidney stones or low bone density history."
            )
            return answer, "interpret_calcium_intake"

    return None


def _detect_intent_type(query: str) -> str:
    q = _clean_query(query)
    if any(_contains_term(q, term) for term in RISK_INTENT_TERMS):
        return "risk"
    if any(_contains_term(q, term) for term in RECOVERY_INTENT_TERMS):
        return "recovery"
    if any(_contains_term(q, term) for term in TREATMENT_INTENT_TERMS):
        return "treatment"
    if any(_contains_term(q, term) for term in PREVENTION_INTENT_TERMS):
        return "prevention"
    if any(_contains_term(q, term) for term in CAUSE_INTENT_TERMS):
        return "cause"
    return "general"


def _context_k_for_query(gap: float, intent_type: str) -> int:
    if gap < 0.3:
        return 3
    if intent_type in {"treatment", "prevention", "risk", "recovery"}:
        return 3
    return 2


def _extractive_context_answer(context: str, query: str, intent_type: str) -> str:
    """Deterministic context-grounded response used when LLM is unavailable."""
    chunks = [line.strip()[2:].strip() for line in context.splitlines() if line.strip().startswith("-")]
    chunks = [c for c in chunks if c]
    if not chunks:
        return (
            "I can help with bone health basics like osteoporosis prevention, exercise, diet, and fall safety. "
            "Please try again shortly for a detailed response."
        )

    lead = {
        "risk": "Key risks and safety points for your question:",
        "cause": "Main likely causes and contributing factors:",
        "prevention": "Practical prevention steps from the available guidance:",
        "treatment": "Potential management and medication considerations from the available guidance:",
        "recovery": "Recovery-focused guidance from the available information:",
    }.get(intent_type, "Relevant bone-health guidance based on available context:")

    selected = chunks[:4]
    bullets = "\n".join(f"- {c}" for c in selected)
    action_steps = "\n".join(
        f"{idx}. {step}"
        for idx, step in enumerate(
            [
                "Prioritize the points above that match your current symptoms and risk factors.",
                "Turn these into a weekly routine with specific food, activity, and fall-prevention actions.",
                "Review progress in 4-8 weeks and adjust with a doctor if symptoms persist or worsen.",
            ],
            start=1,
        )
    )
    safety_tail = (
        "This is educational information and not a medical diagnosis. "
        "For urgent symptoms or medication decisions, consult a doctor or other licensed medical professional."
    )
    if intent_type == "treatment":
        safety_tail = (
            "This is educational information and not a medical diagnosis. "
            "Medication choices, dosing, and duration must be individualized by a doctor or other licensed medical professional."
        )

    return (
        f"{lead}\n"
        f"Key points from available guidance:\n{bullets}\n"
        f"Practical next steps:\n{action_steps}\n"
        f"{safety_tail}"
    )


def _is_strictly_off_topic(query: str) -> bool:
    q = _clean_query(query)
    core_hits, support_hits, _off_topic_hits = _intent_profile(q)
    strict_hits = sum(1 for term in OFF_TOPIC_STRICT_TERMS if _contains_term(q, term))
    return strict_hits > 0 and core_hits == 0 and support_hits == 0


def _domain_reject_response() -> str:
    return "I can only help with bone health and osteoporosis topics."


def _merge_hybrid_results(
    vector_results: list[tuple[str, float]],
    keyword_results: list[tuple[str, float]],
) -> list[tuple[str, float, float]]:
    merged: dict[str, dict[str, float]] = {}

    for text, dist in vector_results:
        merged[text] = {"dist": dist, "kw": 0.0}

    for text, kw_score in keyword_results:
        if text not in merged:
            merged[text] = {"dist": WEAK_MATCH_MAX + 0.25, "kw": kw_score}
        else:
            merged[text]["kw"] = max(merged[text]["kw"], kw_score)

    return [(text, vals["dist"], vals["kw"]) for text, vals in merged.items()]


def _format_context(chunks: list[tuple[str, float]], max_chunks: int) -> str:
    lines = [f"- {text}" for text, _dist in chunks[:max_chunks]]
    return "\n\n".join(lines)


def _llm_fallback_hierarchy(
    user_input: str,
    history: list[dict[str, str]] | None,
    existing_faq_answer: str | None = None,
    skip_general_llm: bool = False,
    timeout_sec: int = 5,
) -> tuple[str, str]:
    """Fallback order: General LLM -> FAQ -> Static response."""
    if not skip_general_llm:
        general = generate_general_answer(user_input, history=history, timeout_sec=timeout_sec)
        if not is_llm_unavailable_response(general):
            return general, "fallback_general"

    faq_answer = existing_faq_answer or _get_faq_response(user_input)
    if faq_answer:
        return faq_answer, "fallback_faq"

    return (
        "I can help with bone health basics like osteoporosis prevention, exercise, diet, and fall safety. "
        "Please try again shortly for a detailed response.",
        "fallback_static",
    )


def _finalize_response(
    answer: str,
    confidence: str,
    route: str,
    best_distance: float,
    gap: float,
    context_count: int,
    timing_ms: dict[str, float] | None,
    return_meta: bool,
    ranking_meta: dict[str, Any] | None = None,
) -> str | dict[str, Any]:
    if not return_meta:
        return answer
    return {
        "answer": answer,
        "confidence": confidence,
        "route": route,
        "best_distance": None if math.isinf(best_distance) else round(best_distance, 4),
        "gap": None if math.isinf(gap) else round(gap, 4),
        "context_count": int(context_count),
        "timing_ms": timing_ms or {},
        "ranking_meta": ranking_meta or {},
    }


def _is_greeting_or_small_talk(query: str) -> bool:
    """Detect if query is a greeting or small talk."""
    q = _clean_query(query)
    return any(_contains_term(q, term) for term in SMALL_TALK)


def _record_fallback(source: str) -> None:
    """Track fallback event for production monitoring."""
    _FALLBACK_STATS["fallback_queries"] += 1
    if source == "rag_strong":
        _FALLBACK_STATS["rag_strong_fallback"] += 1
    elif source == "rag_weak":
        _FALLBACK_STATS["rag_weak_fallback"] += 1
    elif source == "guard":
        _FALLBACK_STATS["guard_fallback"] += 1
    elif source == "no_retrieval":
        _FALLBACK_STATS["no_retrieval_fallback"] += 1


def get_fallback_rate(threshold_queries: int = 10) -> dict[str, Any]:
    """Get current fallback rates. Returns None if insufficient data."""
    total = _FALLBACK_STATS["total_queries"]
    if total < threshold_queries:
        return {"status": "insufficient_data", "total": total}
    
    fallback = _FALLBACK_STATS["fallback_queries"]
    rate = (fallback / total * 100) if total > 0 else 0.0
    
    return {
        "status": "ok",
        "total_queries": total,
        "fallback_count": fallback,
        "overall_fallback_rate_pct": round(rate, 2),
        "rag_strong_fallback": _FALLBACK_STATS["rag_strong_fallback"],
        "rag_weak_fallback": _FALLBACK_STATS["rag_weak_fallback"],
        "guard_fallback": _FALLBACK_STATS["guard_fallback"],
        "no_retrieval_fallback": _FALLBACK_STATS["no_retrieval_fallback"],
    }


def _is_health_related(query: str, best_distance: float, best_keyword_score: float) -> bool:
    core_hits, support_hits, off_topic_hits = _intent_profile(query)
    off_topic_hits = _effective_off_topic_hits(query, core_hits, support_hits, off_topic_hits)
    medical_hits = _strict_medical_hits(query)
    if _is_strictly_off_topic(query):
        return False

    embedding_hit = best_distance < GUARD_MAX
    keyword_hit = best_keyword_score >= 0.8

    intent_score = (core_hits * 1.2) + (min(support_hits, 2) * 0.4)
    if embedding_hit:
        intent_score += 0.7
    if keyword_hit:
        intent_score += 0.7

    # If explicit off-topic intent appears with no core bone signal, block it.
    if off_topic_hits > 0 and core_hits == 0:
        return False

    # Accept strong core-topic queries quickly.
    if core_hits > 0 and intent_score >= 1.2:
        return True

    # Accept medically-specific safety/treatment questions when retrieval signals are strong enough.
    if medical_hits > 0 and off_topic_hits == 0 and (best_distance < WEAK_MATCH_MAX or best_keyword_score >= 1.8):
        return True

    # Accept typo/rare-term queries if retrieval evidence is strong and not off-topic.
    if off_topic_hits == 0 and (best_distance < 1.05 or best_keyword_score >= 2.0):
        return True

    # For generic health wording, require stronger vector/sparse evidence.
    if support_hits > 0 and best_distance < 1.25 and best_keyword_score >= 2.5:
        return True

    return intent_score >= 1.8 and (core_hits > 0 or (support_hits >= 2 and (embedding_hit or keyword_hit)))


def _get_faq_response(query: str) -> str | None:
    q = _clean_query(query)
    for patterns, answer in FAQ_RULES:
        if any(pattern in q for pattern in patterns):
            return answer
        for pattern in patterns:
            tokens = [t for t in pattern.split() if t not in {"what", "is", "explain"}]
            if len(tokens) >= 2 and all(_contains_term(q, tok) for tok in tokens):
                return answer
    return None


def _get_greeting_response(query: str) -> str:
    """Return friendly greeting response."""
    q = _clean_query(query)

    if any(_contains_term(q, g) for g in GREETINGS):
        return "Hello! I'm OsteoCare+ AI, your bone health assistant. I can help you learn about osteoporosis, exercise, diet, and preventing fractures. What would you like to know?"

    if any(_contains_term(q, t) for t in THANKS):
        return "You're welcome! 😊 Feel free to ask me any questions about bone health. I'm here to help!"

    return "Hi there! How can I assist you with bone health today?"


def chatbot_response(
    user_input: str,
    history: list[dict[str, str]] | None = None,
    return_meta: bool = False,
) -> str | dict[str, Any]:
    """Main chatbot entry point with fallback logic.

    Strategy:
    1. Check for greetings/small talk → answer directly
    2. Check FAQ shortcuts → answer directly
    3. Retrieve scored chunks and compute top-1 baseline
    4. Check domain guardrails (keyword + embedding)
    5. Rank and filter chunks using hybrid score
    6. Strong/weak/fallback route based on top-1 baseline
    """

    started_at = time.perf_counter()
    timing_ms: dict[str, float] = {}

    def _mark(label: str, phase_started_at: float) -> None:
        timing_ms[label] = round((time.perf_counter() - phase_started_at) * 1000.0, 2)

    _FALLBACK_STATS["total_queries"] += 1
    user_input = user_input.strip()
    if not user_input:
        timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
        return _finalize_response(
            "Please ask me a question about bone health!",
            confidence="low",
            route="empty",
            best_distance=float("inf"),
            gap=float("inf"),
            context_count=0,
            timing_ms=timing_ms,
            return_meta=return_meta,
        )

    # Step 1: Handle greetings/small talk
    if _is_greeting_or_small_talk(user_input):
        timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
        return _finalize_response(
            _get_greeting_response(user_input),
            confidence="high",
            route="small_talk",
            best_distance=float("inf"),
            gap=float("inf"),
            context_count=0,
            timing_ms=timing_ms,
            return_meta=return_meta,
        )

    _ensure_cache_fresh()
    cleaned_query = _clean_query(user_input)

    interpreted = _interpretation_response(user_input)
    if interpreted is not None:
        answer, route = interpreted
        _consistency_cache_set(_build_cache_key(cleaned_query, history), answer, route, "high")
        timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
        return _finalize_response(
            answer,
            confidence="high",
            route=route,
            best_distance=float("inf"),
            gap=float("inf"),
            context_count=0,
            timing_ms=timing_ms,
            return_meta=return_meta,
        )

    practical_mode = _is_practical_query(cleaned_query)
    profile_hint = _profile_hint(cleaned_query, history)

    if _within_budget(started_at) and not _should_skip_rewrite(cleaned_query, history):
        rewrite_started_at = time.perf_counter()
        rewritten_query, rewrite_confidence = _rewrite_query_cached(cleaned_query, history)
        _mark("rewrite", rewrite_started_at)
    else:
        rewritten_query, rewrite_confidence = cleaned_query, "low"
        timing_ms["rewrite"] = 0.0
    canonical_query = rewritten_query if rewrite_confidence in {"high", "medium"} else cleaned_query

    # Preserve conversational continuity for short follow-ups when rewrite confidence is low.
    if history and rewrite_confidence == "low" and len(cleaned_query.split()) <= 6:
        topic_hint = _history_topic_hint(history)
        if topic_hint:
            canonical_query = f"{canonical_query} {topic_hint}".strip()

    cache_key = _build_cache_key(canonical_query, history)
    cached = _consistency_cache_get(cache_key)
    if cached is not None:
        cached_answer, cached_route, cached_confidence = cached
        timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
        return _finalize_response(
            cached_answer,
            confidence=cached_confidence,
            route=f"consistency_cache_{cached_route}",
            best_distance=float("inf"),
            gap=float("inf"),
            context_count=0,
            timing_ms=timing_ms,
            return_meta=return_meta,
        )

    # Step 2: FAQ short-circuit to reduce unnecessary LLM calls
    faq_answer = _get_faq_response(user_input)
    if faq_answer:
        _consistency_cache_set(cache_key, faq_answer, "faq", "high")
        timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
        return _finalize_response(
            faq_answer,
            confidence="high",
            route="faq",
            best_distance=float("inf"),
            gap=float("inf"),
            context_count=0,
            timing_ms=timing_ms,
            return_meta=return_meta,
        )

    # Step 3: Retrieve scored chunks and compute top-1 baseline
    retrieval_started_at = time.perf_counter()
    scored_results = retrieve_with_scores(canonical_query, k=VECTOR_TOP_K)
    sparse_results = keyword_search(canonical_query, k=SPARSE_TOP_K)
    hybrid_results = hybrid_retrieve(canonical_query, vector_k=VECTOR_TOP_K, sparse_k=SPARSE_TOP_K)
    _mark("retrieval", retrieval_started_at)

    best_distance = scored_results[0][1] if scored_results else float("inf")
    second_distance = scored_results[1][1] if len(scored_results) > 1 else float("inf")
    gap = (
        float("inf")
        if math.isinf(best_distance) or math.isinf(second_distance)
        else max(0.0, second_distance - best_distance)
    )
    best_keyword_score = sparse_results[0][1] if sparse_results else 0.0

    # Step 4: Domain guardrail (keyword + embedding)
    if not _is_health_related(cleaned_query, best_distance, best_keyword_score):
        _record_fallback("guard")
        timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
        return _finalize_response(
            _domain_reject_response(),
            confidence="low",
            route="domain_guard",
            best_distance=best_distance,
            gap=gap,
            context_count=0,
            timing_ms=timing_ms,
            return_meta=return_meta,
        )

    # Step 5: Detect mixed intent and scope the answer to health-only intent.
    core_hits, support_hits, off_topic_hits = _intent_profile(cleaned_query)
    off_topic_hits = _effective_off_topic_hits(cleaned_query, core_hits, support_hits, off_topic_hits)
    intent_type = _detect_intent_type(cleaned_query)
    mixed_intent = off_topic_hits > 0 and (core_hits > 0 or support_hits > 0)

    # Step 6: Adaptive rerank policy: skip or shrink rerank based on confidence + remaining budget.
    rerank_started_at = time.perf_counter()
    remaining_before_rerank = _remaining_total_budget(started_at)
    skip_rerank_signal = best_distance < RERANK_SKIP_DISTANCE_MAX and gap > RERANK_SKIP_GAP_MIN
    skip_rerank_budget = remaining_before_rerank < RERANK_EARLY_EXIT_MIN_BUDGET_SEC
    cheap_ranked = fast_rank_hybrid_candidates(canonical_query, hybrid_results, top_k=3)
    ranking_meta: dict[str, Any] = {
        "mode": "cheap",
        "rerank_used": False,
        "dynamic_top_k": _dynamic_rerank_top_k(gap),
        "cheap_rerank_changed": False,
        "remaining_budget_sec": round(remaining_before_rerank, 3),
    }

    dynamic_top_k = _dynamic_rerank_top_k(gap)

    if skip_rerank_signal or skip_rerank_budget:
        reranked = cheap_ranked[:dynamic_top_k]
        ranking_meta["mode"] = "cheap_skip_signal" if skip_rerank_signal else "cheap_skip_budget"
        timing_ms["rerank"] = 0.0
    else:
        rerank_top = RERANK_TOP_K
        rerank_output_top_k = dynamic_top_k
        if remaining_before_rerank < RERANK_PARTIAL_MAX_BUDGET_SEC:
            rerank_output_top_k = min(dynamic_top_k, max(1, min(3, RERANK_PARTIAL_TOP_K)))
            rerank_top = rerank_output_top_k
            ranking_meta["mode"] = "rerank_partial"
        else:
            ranking_meta["mode"] = "rerank_full"

        reranked = rerank_hybrid_candidates(
            canonical_query,
            hybrid_results,
            top_k=rerank_output_top_k,
            rerank_top=rerank_top,
            max_rerank_sec=min(RERANK_MAX_TIME_SEC, max(0.2, remaining_before_rerank)),
            early_stop_score=RERANK_EARLY_STOP_SCORE,
        )
        ranking_meta["rerank_used"] = True
        ranking_meta["rerank_output_top_k"] = rerank_output_top_k
        cheap_top = cheap_ranked[0][0] if cheap_ranked else ""
        rerank_top_text = reranked[0][0] if reranked else ""
        ranking_meta["cheap_rerank_changed"] = bool(cheap_top and rerank_top_text and cheap_top != rerank_top_text)
        _mark("rerank", rerank_started_at)

    # Step 7: Strong/weak/fallback route based on top-1 baseline
    if best_distance < STRONG_MATCH_MAX and gap > STRONG_GAP_MIN:
        filtered = [
            (text, dist)
            for text, dist, kw, rr in reranked
            if dist < WEAK_MATCH_MAX or kw >= 1.2 or rr >= 0.1
        ]
        if filtered:
            context_k = _context_k_for_query(gap, intent_type)
            context = _format_context(filtered, max_chunks=context_k)
            pre_confidence_score = _compute_confidence_score(best_distance, gap, len(filtered[:context_k]))

            remaining_before_answer = _remaining_total_budget(started_at)
            if remaining_before_answer <= 0.0:
                answer, route = _fast_timeout_fallback()
                confidence = "low"
                _record_fallback("no_retrieval")
                timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
                return _finalize_response(
                    answer,
                    confidence=confidence,
                    route=route,
                    best_distance=best_distance,
                    gap=gap,
                    context_count=0,
                    timing_ms=timing_ms,
                    return_meta=return_meta,
                    ranking_meta=ranking_meta,
                )

            answer_started_at = time.perf_counter()
            answer = generate_rag_answer(
                context,
                user_input,
                history=history,
                timeout_sec=max(1, int(min(remaining_before_answer, REQUEST_BUDGET_SEC))),
                intent_type=intent_type,
                require_multi_aspect=context_k >= 3,
                practical_mode=practical_mode,
                profile_hint=profile_hint,
            )
            _mark("answer_generation", answer_started_at)
            route = "rag_strong"
            grading_level = "NO_CHECK"

            if is_llm_unavailable_response(answer):
                answer = _extractive_context_answer(context, user_input, intent_type)
                route = "rag_strong_extractive_no_llm"
            elif (
                _within_budget(started_at)
                and pre_confidence_score < SELF_CHECK_SKIP_CONFIDENCE
                and _remaining_total_budget(started_at) >= MIN_SELF_CHECK_TIMEOUT_SEC
            ):
                self_check_started_at = time.perf_counter()
                grading_level = answer_supported_by_context(
                    context,
                    user_input,
                    answer,
                    history=history,
                    mode=_self_check_mode(user_input),
                    timeout_sec=max(1, int(min(_remaining_total_budget(started_at), 6.0))),
                )
                _mark("self_check", self_check_started_at)
                
                # strict mode: reject only UNSUPPORTED
                # relaxed mode: accept FULLY and PARTIALLY, reject only UNSUPPORTED
                should_fallback = grading_level == "UNSUPPORTED"
                
                if should_fallback:
                    answer = _extractive_context_answer(context, user_input, intent_type)
                    route = "rag_strong_selfcheck_unsupported_extractive"
                else:
                    route = f"rag_strong_selfcheck_{grading_level}"
            else:
                route = "rag_strong_selfcheck_skipped_high_confidence"

            if mixed_intent:
                answer = (
                    "I will focus only on the bone-health part of your question. "
                    + answer
                )

            confidence = _compute_confidence(best_distance, gap, len(filtered[:3]))
            if confidence == "low" and off_topic_hits > 0 and core_hits == 0:
                _record_fallback("guard")
                answer = _domain_reject_response()
                route = "domain_guard"
                confidence = "low"
            _consistency_cache_set(cache_key, answer, route, confidence)
            timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
            return _finalize_response(
                answer,
                confidence=confidence,
                route=route,
                best_distance=best_distance,
                gap=gap,
                context_count=len(filtered[:context_k]),
                timing_ms=timing_ms,
                return_meta=return_meta,
                ranking_meta=ranking_meta,
            )

    elif best_distance < WEAK_MATCH_MAX:
        filtered = [
            (text, dist)
            for text, dist, kw, rr in reranked
            if dist < WEAK_MATCH_MAX or kw >= 1.2 or rr >= 0.1
        ]
        if filtered:
            context_k = _context_k_for_query(gap, intent_type)
            context = _format_context(filtered, max_chunks=context_k)
            remaining_before_answer = _remaining_total_budget(started_at)
            if remaining_before_answer <= 0.0:
                answer, route = _fast_timeout_fallback()
                confidence = "low"
                _record_fallback("no_retrieval")
                timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
                return _finalize_response(
                    answer,
                    confidence=confidence,
                    route=route,
                    best_distance=best_distance,
                    gap=gap,
                    context_count=0,
                    timing_ms=timing_ms,
                    return_meta=return_meta,
                    ranking_meta=ranking_meta,
                )
            answer_started_at = time.perf_counter()
            answer = generate_rag_answer(
                context,
                user_input,
                history=history,
                timeout_sec=max(1, int(min(remaining_before_answer, REQUEST_BUDGET_SEC))),
                intent_type=intent_type,
                require_multi_aspect=context_k >= 3,
                practical_mode=practical_mode,
                profile_hint=profile_hint,
            )
            _mark("answer_generation", answer_started_at)
            route = "rag_weak"

            if is_llm_unavailable_response(answer):
                answer = _extractive_context_answer(context, user_input, intent_type)
                route = "rag_weak_extractive_no_llm"

            confidence = _compute_confidence(best_distance, gap, len(filtered[:2]))
            if confidence == "low" and (off_topic_hits > 0 or _is_strictly_off_topic(cleaned_query)) and core_hits == 0:
                _record_fallback("guard")
                answer = _domain_reject_response()
                route = "domain_guard"
                confidence = "low"
            _consistency_cache_set(cache_key, answer, route, confidence)
            timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
            return _finalize_response(
                answer,
                confidence=confidence,
                route=route,
                best_distance=best_distance,
                gap=gap,
                context_count=len(filtered[:context_k]),
                timing_ms=timing_ms,
                return_meta=return_meta,
                ranking_meta=ranking_meta,
            )

    remaining_for_fallback = _remaining_total_budget(started_at)
    if remaining_for_fallback <= 0.0:
        answer, fallback_route = _fast_timeout_fallback()
    else:
        answer, fallback_route = _llm_fallback_hierarchy(
            user_input,
            history,
            existing_faq_answer=faq_answer,
            timeout_sec=max(1, int(min(remaining_for_fallback, REQUEST_BUDGET_SEC))),
        )
    if _is_strictly_off_topic(cleaned_query):
        answer = _domain_reject_response()
        fallback_route = "domain_guard"
    final_confidence = _compute_confidence(best_distance, gap, 0)
    _record_fallback("no_retrieval")
    _consistency_cache_set(cache_key, answer, fallback_route, final_confidence)
    timing_ms["total"] = round((time.perf_counter() - started_at) * 1000.0, 2)
    return _finalize_response(
        answer,
        confidence=final_confidence,
        route=fallback_route,
        best_distance=best_distance,
        gap=gap,
        context_count=0,
        timing_ms=timing_ms,
        return_meta=return_meta,
        ranking_meta=ranking_meta,
    )

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
import os
import re
import threading

import ollama


SUMMARY_TOPICS = (
    "osteoporosis",
    "fracture",
    "calcium",
    "vitamin d",
    "exercise",
    "diet",
    "dexa",
    "bmi",
    "fall",
)

DEFAULT_TIMEOUT_SEC = 20
DEFAULT_RETRIES = 1
MAX_CONCURRENT_LLM_CALLS = 4
MAX_QUEUE_WAIT_SEC = 1.0
DEFAULT_MODEL = os.getenv("OLLAMA_MODEL", "mistral")
FAST_MODEL = os.getenv("OLLAMA_FAST_MODEL", DEFAULT_MODEL)
RAG_MODEL = os.getenv("OLLAMA_RAG_MODEL", FAST_MODEL)
LLM_UNAVAILABLE_MESSAGE = (
    "I am having trouble reaching the language model right now. "
    "Please try again in a moment."
)
_LLM_SEMAPHORE = threading.BoundedSemaphore(MAX_CONCURRENT_LLM_CALLS)

_STOPWORDS = {
    "the", "and", "for", "with", "from", "that", "this", "what", "when", "where",
    "how", "why", "can", "could", "should", "would", "into", "about", "your", "their",
    "have", "has", "had", "will", "does", "did", "are", "was", "were", "help", "tips",
}

_MEDICAL_ENTITY_TERMS = {
    "osteoporosis", "osteopenia", "fracture", "fractures", "calcium", "vitamin", "dexa",
    "bmd", "bone", "bones", "bisphosphonate", "bisphosphonates", "steroid", "steroids",
    "menopause", "postmenopause", "arthritis", "fall", "falls", "hip", "spine",
}


def _ollama_chat(prompt: str, model: str = DEFAULT_MODEL) -> str:
    response = ollama.chat(
        model=model,
        messages=[{"role": "user", "content": prompt}],
    )
    return response["message"]["content"]


def _safe_ollama_chat(
    prompt: str,
    timeout_sec: int = DEFAULT_TIMEOUT_SEC,
    retries: int = DEFAULT_RETRIES,
    model: str = DEFAULT_MODEL,
) -> str:
    attempts = max(0, retries) + 1
    last_error: Exception | None = None

    for _ in range(attempts):
        executor: ThreadPoolExecutor | None = None
        acquired = False
        try:
            acquired = _LLM_SEMAPHORE.acquire(timeout=MAX_QUEUE_WAIT_SEC)
            if not acquired:
                last_error = TimeoutError("LLM queue wait exceeded")
                continue

            executor = ThreadPoolExecutor(max_workers=1)
            future = executor.submit(_ollama_chat, prompt, model)
            result = future.result(timeout=timeout_sec)
            executor.shutdown(wait=False, cancel_futures=True)
            return result
        except FutureTimeoutError:
            last_error = TimeoutError("LLM request timed out")
            if executor is not None:
                executor.shutdown(wait=False, cancel_futures=True)
        except Exception as exc:  # pragma: no cover - runtime network/model errors
            last_error = exc
            if executor is not None:
                executor.shutdown(wait=False, cancel_futures=True)
        finally:
            if acquired:
                _LLM_SEMAPHORE.release()

    if last_error:
        return LLM_UNAVAILABLE_MESSAGE
    return "I am temporarily unavailable. Please try again."


def is_llm_unavailable_response(text: str) -> bool:
    return text.strip().lower().startswith("i am having trouble reaching the language model")


def _extract_key_entities(text: str) -> set[str]:
    tokens = re.findall(r"[a-z0-9]+", text.lower())
    entities: set[str] = set()
    for token in tokens:
        if token in _MEDICAL_ENTITY_TERMS:
            entities.add(token)
            continue
        if len(token) >= 5 and token not in _STOPWORDS:
            entities.add(token)
    return entities


def _build_history_summary(history: list[dict[str, str]] | None) -> str:
    if not history:
        return ""

    window_size = 6
    older_history = history[:-window_size] if len(history) > window_size else history

    user_texts = [
        str(item.get("content", "")).strip().lower()
        for item in older_history
        if str(item.get("role", "")).strip().lower() == "user"
    ]
    user_texts = [text for text in user_texts if text]
    if not user_texts:
        return ""

    topic_hits = [topic for topic in SUMMARY_TOPICS if any(topic in text for text in user_texts)]
    topic_summary = ", ".join(topic_hits[:3]) if topic_hits else "bone health"

    latest_user = user_texts[-1]
    if len(latest_user) > 100:
        latest_user = latest_user[:100].rstrip() + "..."

    return (
        "Conversation summary: "
        f"User has been discussing {topic_summary}. "
        f"Latest user focus: {latest_user}"
    )


def _format_history(history: list[dict[str, str]] | None) -> str:
    if not history:
        return ""

    summary = _build_history_summary(history)

    lines: list[str] = []
    window_size = 6
    for item in history[-window_size:]:
        role = str(item.get("role", "")).strip().lower()
        content = str(item.get("content", "")).strip()
        if not content or role not in {"user", "assistant"}:
            continue
        role_label = "User" if role == "user" else "Assistant"
        lines.append(f"{role_label}: {content}")

    if not lines and not summary:
        return ""

    blocks: list[str] = []
    if summary:
        blocks.append(summary)
    if lines:
        blocks.append("Conversation history:\n" + "\n".join(lines))
    return "\n\n".join(blocks)


def generate_rag_answer(
    context: str,
    question: str,
    history: list[dict[str, str]] | None = None,
    timeout_sec: int = DEFAULT_TIMEOUT_SEC,
    intent_type: str = "general",
    require_multi_aspect: bool = False,
    practical_mode: bool = False,
    profile_hint: str = "",
) -> str:
    """Generate answer using context (RAG mode)."""
    history_block = _format_history(history)

    aspect_rule = (
        "Answer must cover all major aspects asked by the user. "
        "Do not give a single-point answer when multiple factors are requested."
        if require_multi_aspect
        else "Answer directly and include relevant supporting factors from context."
    )

    intent_rule = {
        "risk": "Focus on risks, harms, warning signs, and safety cautions.",
        "cause": "Focus on causes and contributing factors.",
        "prevention": "Focus on prevention steps and practical habits.",
        "treatment": "Focus on treatment/management options and when to seek care.",
        "recovery": "Focus on recovery guidance, progression, and precautions.",
    }.get(intent_type, "Keep response aligned to the user intent.")

    practical_rule = (
        "Because this is a practical question: include 2-3 concrete examples, explicit actionable steps, "
        "and a short 'what to do next' section."
        if practical_mode
        else ""
    )

    profile_rule = (
        f"Personalization hint: {profile_hint}. Adapt advice to this profile without changing medical safety."
        if profile_hint.strip()
        else ""
    )

    prompt = f"""You are a medical assistant specializing in bone health and osteoporosis.

Use the context below to answer the user's question accurately.
If relevant information is in the context, prioritize it.
If the context doesn't have the answer, provide general helpful information.
{aspect_rule}
{intent_rule}
{practical_rule}
{profile_rule}
When relevant, include practical and actionable guidance (for example: sample foods, exercise examples, safety checks, or follow-up steps).
Prefer short structured sections such as: key points, practical steps, and when to seek clinical care.

{history_block}

Context:
{context}

Question: {question}

Answer helpfully with enough depth to be useful while staying concise."""

    return _safe_ollama_chat(prompt, timeout_sec=timeout_sec, model=RAG_MODEL)


def generate_general_answer(
    question: str,
    history: list[dict[str, str]] | None = None,
    timeout_sec: int = DEFAULT_TIMEOUT_SEC,
) -> str:
    """Generate answer without context (fallback mode)."""
    history_block = _format_history(history)

    prompt = f"""You are a friendly medical assistant specializing in bone health and osteoporosis.

{history_block}

The user asked: {question}

Respond helpfully and conversationally. If they greeted you, greet them back.
Focus on bone health, osteoporosis prevention, exercise, diet, and related topics.
Always include a disclaimer that this is educational and not a medical diagnosis.

Keep responses concise and friendly."""

    return _safe_ollama_chat(prompt, timeout_sec=timeout_sec, model=FAST_MODEL)


def answer_supported_by_context(
    context: str,
    question: str,
    answer: str,
    history: list[dict[str, str]] | None = None,
    mode: str = "strict",
    timeout_sec: int = 12,
) -> str:
    """Graded LLM self-check: FULLY_SUPPORTED, PARTIALLY_SUPPORTED, or UNSUPPORTED.
    
    Returns one of:
    - "FULLY_SUPPORTED": all factual claims explicitly in context
    - "PARTIALLY_SUPPORTED": most claims supported, minor gaps acceptable
    - "UNSUPPORTED": major claims missing or contradicted
    """
    history_block = _format_history(history)

    mode = mode.strip().lower()
    if mode not in {"strict", "relaxed"}:
        mode = "strict"

    if mode == "strict":
        criteria = (
            "Reply with a single word:\n"
            "- FULLY: every factual claim is explicitly supported by context\n"
            "- PARTIAL: most claims supported, minor inferences acceptable but marked\n"
            "- UNSUPPORTED: major claims missing support or contradicted"
        )
    else:
        criteria = (
            "Reply with a single word:\n"
            "- FULLY: all key claims are well-supported by context\n"
            "- PARTIAL: answer is mostly supported, minor gaps acceptable\n"
            "- UNSUPPORTED: answer contradicts context or is majorly unsupported"
        )

    prompt = f"""You are a factual grading assistant.

{history_block}

Context:
{context}

Question: {question}

Answer:
{answer}

Task: Reply with exactly one word: FULLY, PARTIAL, or UNSUPPORTED.
{criteria}
Do not explain."""

    verdict = _safe_ollama_chat(prompt, timeout_sec=timeout_sec, retries=0, model=FAST_MODEL).strip().upper()
    
    # Map response to canonical levels
    if verdict.startswith("FULL"):
        return "FULLY_SUPPORTED"
    elif verdict.startswith("PARTIAL") or verdict.startswith("PART"):
        return "PARTIALLY_SUPPORTED"
    else:
        return "UNSUPPORTED"


def rewrite_query_for_retrieval(
    question: str,
    history: list[dict[str, str]] | None = None,
) -> tuple[str, str]:
    """Rewrite noisy user text into a retrieval-friendly medical query."""
    question = str(question).strip()
    if not question:
        return "", "low"

    # Very short queries are usually already normalized enough.
    if len(question.split()) <= 2:
        return question, "high"

    history_block = _format_history(history)
    prompt = f"""You rewrite user questions for retrieval in a bone-health assistant.

{history_block}

Original question: {question}

Rules:
- Keep core intent unchanged.
- Keep it short (max 16 words).
- Keep medical terms when present.
- Preserve key entities exactly when possible.
- Fix spelling only if obvious.
- Output only the rewritten query text.
"""

    rewritten = _safe_ollama_chat(prompt, timeout_sec=8, retries=0, model=FAST_MODEL).strip()
    if not rewritten or is_llm_unavailable_response(rewritten):
        return question, "low"

    rewritten = " ".join(rewritten.split())
    if len(rewritten) > 180:
        rewritten = rewritten[:180].strip()

    original_entities = _extract_key_entities(question)
    rewritten_entities = _extract_key_entities(rewritten)

    if not original_entities:
        preserve_ratio = 1.0
    else:
        preserve_ratio = len(original_entities & rewritten_entities) / max(1, len(original_entities))

    if preserve_ratio < 0.5:
        return question, "low"
    if preserve_ratio < 0.75:
        return rewritten or question, "medium"
    return rewritten or question, "high"

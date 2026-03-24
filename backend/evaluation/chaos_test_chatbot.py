from __future__ import annotations

import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import chatbot


def _run_case(name: str, query: str, patch_mode: str) -> dict:
    original = {
        "generate_rag_answer": chatbot.generate_rag_answer,
        "generate_general_answer": chatbot.generate_general_answer,
        "answer_supported_by_context": chatbot.answer_supported_by_context,
        "rewrite_query_for_retrieval": chatbot.rewrite_query_for_retrieval,
    }

    try:
        if patch_mode == "normal":
            chatbot.generate_rag_answer = lambda *a, **k: "Structured bone-health response"
            chatbot.generate_general_answer = lambda *a, **k: "General bone-health fallback"
        elif patch_mode == "llm_down":
            chatbot.generate_rag_answer = lambda *a, **k: "I am having trouble reaching the language model right now. Please try again in a moment."
            chatbot.generate_general_answer = lambda *a, **k: "I am having trouble reaching the language model right now. Please try again in a moment."
        elif patch_mode == "bad_rewrite":
            chatbot.generate_rag_answer = lambda *a, **k: "Structured bone-health response"
            chatbot.generate_general_answer = lambda *a, **k: "General bone-health fallback"
            chatbot.rewrite_query_for_retrieval = lambda q, history=None: ("osteoporosis medication", "medium")
        elif patch_mode == "weak_grounding":
            chatbot.generate_rag_answer = lambda *a, **k: "Unsupported claim heavy response"
            chatbot.generate_general_answer = lambda *a, **k: "General bone-health fallback"
            chatbot.answer_supported_by_context = lambda *a, **k: "UNSUPPORTED"
        elif patch_mode == "multi_turn_ambiguity":
            chatbot.generate_rag_answer = lambda *a, **k: "Context-aware prevention and diet guidance"
            chatbot.generate_general_answer = lambda *a, **k: "General bone-health fallback"
            chatbot.rewrite_query_for_retrieval = lambda q, history=None: (q, "high")
        elif patch_mode == "conflicting_signals":
            chatbot.generate_rag_answer = lambda *a, **k: "Partially grounded response with caveats"
            chatbot.generate_general_answer = lambda *a, **k: "General bone-health fallback"
            chatbot.answer_supported_by_context = lambda *a, **k: "PARTIALLY_SUPPORTED"
        elif patch_mode == "partial_grounding_noisy":
            chatbot.generate_rag_answer = lambda *a, **k: "Some relevant info mixed with noisy details"
            chatbot.generate_general_answer = lambda *a, **k: "General bone-health fallback"
            chatbot.answer_supported_by_context = lambda *a, **k: "PARTIALLY_SUPPORTED"
        elif patch_mode == "contradictory_query":
            chatbot.generate_rag_answer = lambda *a, **k: "Calcium supports bone health, but overdose can increase health risks if unsupervised."
            chatbot.generate_general_answer = lambda *a, **k: "General bone-health fallback"
            chatbot.answer_supported_by_context = lambda *a, **k: "PARTIALLY_SUPPORTED"
        elif patch_mode == "mixed_vague_typo":
            chatbot.generate_rag_answer = lambda *a, **k: "Focus on bone health basics: weight-bearing exercise, vitamin D, calcium foods, and fall prevention."
            chatbot.generate_general_answer = lambda *a, **k: "General bone-health fallback"
            chatbot.answer_supported_by_context = lambda *a, **k: "PARTIALLY_SUPPORTED"

        history = [{"role": "user", "content": "osteoporosis prevention"}]
        if patch_mode == "multi_turn_ambiguity":
            history = [
                {"role": "user", "content": "osteoporosis"},
                {"role": "assistant", "content": "It is low bone density and fracture risk."},
                {"role": "user", "content": "how to prevent it"},
            ]

        result = chatbot.chatbot_response(
            query,
            history=history,
            return_meta=True,
        )
        if isinstance(result, dict):
            return {"name": name, **result}
        return {"name": name, "answer": str(result), "route": "legacy"}
    finally:
        chatbot.generate_rag_answer = original["generate_rag_answer"]
        chatbot.generate_general_answer = original["generate_general_answer"]
        chatbot.answer_supported_by_context = original["answer_supported_by_context"]
        chatbot.rewrite_query_for_retrieval = original["rewrite_query_for_retrieval"]


def main() -> None:
    scenarios = [
        ("normal", "best exercises for bones", "normal"),
        ("llm_down", "best exercises for bones", "llm_down"),
        ("bad_rewrite", "natural ways to improve bones", "bad_rewrite"),
        ("weak_grounding", "foods for strong bones", "weak_grounding"),
        ("multi_turn_ambiguity", "what about diet?", "multi_turn_ambiguity"),
        ("conflicting_signals", "fracture risk and stock market tips", "conflicting_signals"),
        ("partial_grounding_noisy", "bone pain prevention with random typo vaitamin d", "partial_grounding_noisy"),
        ("contradictory_query", "is calcium always good or can overdose be harmful", "contradictory_query"),
        ("mixed_vague_typo", "how to make bons strnger and also wifi fast", "mixed_vague_typo"),
    ]

    results = []
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = [executor.submit(_run_case, name, query, mode) for name, query, mode in scenarios]
        for fut in as_completed(futures):
            results.append(fut.result())

    results.sort(key=lambda r: r.get("name", ""))
    print(json.dumps({"results": results}, indent=2))


if __name__ == "__main__":
    main()

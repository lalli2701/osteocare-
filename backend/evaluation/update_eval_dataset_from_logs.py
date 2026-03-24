from __future__ import annotations

import argparse
import json
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
DATASET_PATH = BASE_DIR / "chatbot_eval_dataset.json"
GOLD_DATASET_PATH = BASE_DIR / "chatbot_eval_gold_dataset.json"
CANDIDATES_PATH = BASE_DIR / "chatbot_eval_dataset_candidates.json"
GOLD_CANDIDATES_PATH = BASE_DIR / "chatbot_eval_gold_from_logs_candidates.json"


def _load_json(path: Path) -> dict | list:
    if not path.exists():
        return {} if path.suffix == ".json" else []
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {} if path.suffix == ".json" else []


def main() -> None:
    parser = argparse.ArgumentParser(description="Promote curated log candidates into eval dataset.")
    parser.add_argument("--apply", action="store_true", help="Apply approved candidates into dataset.")
    parser.add_argument("--limit", type=int, default=50, help="Max candidates to import when applying.")
    parser.add_argument(
        "--target",
        choices=["default", "gold"],
        default="default",
        help="Which dataset to update.",
    )
    parser.add_argument(
        "--candidates",
        type=str,
        default="",
        help="Optional explicit candidates JSON path.",
    )
    args = parser.parse_args()

    target_path = DATASET_PATH if args.target == "default" else GOLD_DATASET_PATH
    default_candidates = CANDIDATES_PATH if args.target == "default" else GOLD_CANDIDATES_PATH
    candidates_path = Path(args.candidates) if args.candidates else default_candidates

    dataset = _load_json(target_path)
    if not isinstance(dataset, list):
        raise SystemExit("Dataset file is invalid.")

    candidates_doc = _load_json(candidates_path)
    items = []
    if isinstance(candidates_doc, dict):
        items = candidates_doc.get("items", [])
    if not isinstance(items, list):
        items = []

    existing_queries = {str(item.get("query", "")).strip().lower() for item in dataset}

    pending = []
    for item in items:
        query = str(item.get("query", "")).strip()
        if not query:
            continue
        if query.lower() in existing_queries:
            continue
        pending.append(item)

    if not args.apply:
        print(json.dumps({
            "target": args.target,
            "dataset": str(target_path),
            "candidates": str(candidates_path),
            "pending_candidates": len(pending),
            "hint": "Re-run with --apply after manual review/approval.",
        }, indent=2))
        return

    # Apply only candidates explicitly approved=true when present.
    approved = []
    for item in pending:
        if "approved" in item and not bool(item.get("approved")):
            continue
        approved.append(item)

    approved = approved[: max(1, args.limit)]

    additions = []
    for item in approved:
        query = str(item.get("query", "")).strip()
        if args.target == "gold":
            expected_route = str(item.get("expected_route", "")).strip()
            expected_route_prefix = str(item.get("expected_route_prefix", "")).strip()
            additions.append(
                {
                    "query": query,
                    "expected_route": expected_route,
                    "expected_route_prefix": expected_route_prefix,
                    "required_keywords": [str(k) for k in item.get("required_keywords", []) if str(k).strip()],
                    "forbidden_keywords": [str(k) for k in item.get("forbidden_keywords", []) if str(k).strip()],
                    "manual_verified": bool(item.get("manual_verified", False)),
                    "source": str(item.get("source", "logs_real_queries")),
                }
            )
        else:
            additions.append(
                {
                    "query": query,
                    "category": str(item.get("category", "real_world")),
                    "expected": str(item.get("expected", "allow")),
                }
            )

    dataset.extend(additions)
    target_path.write_text(json.dumps(dataset, indent=2), encoding="utf-8")

    print(json.dumps({
        "target": args.target,
        "applied": len(additions),
        "dataset": str(target_path),
        "remaining_pending": max(0, len(pending) - len(additions)),
    }, indent=2))


if __name__ == "__main__":
    main()

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
import hashlib
import math
import os
import re
import time
from collections import Counter
from collections import OrderedDict

import faiss
import numpy as np
from sentence_transformers import CrossEncoder, SentenceTransformer

from knowledge import knowledge

# Lightweight local embedding model suitable for retrieval tasks.
model = SentenceTransformer("all-MiniLM-L6-v2")
_cross_encoder: CrossEncoder | None = None

_embeddings = model.encode(knowledge)
_embeddings = np.array(_embeddings, dtype="float32")

index = faiss.IndexFlatL2(_embeddings.shape[1])
index.add(_embeddings)

_TOKEN_RE = re.compile(r"[a-z0-9]+")
RERANK_CACHE_MAX = 256
_RERANK_CACHE: OrderedDict[
    tuple[str, int, int, str, float, float],
    list[tuple[str, float, float, float]],
] = OrderedDict()


def _tokenize(text: str) -> list[str]:
    return _TOKEN_RE.findall(text.lower())


def _cheap_fusion_score(
    query_terms: set[str],
    item: tuple[str, float, float],
) -> tuple[float, float]:
    text, dist, kw = item
    if math.isinf(dist):
        dist = 3.0

    doc_terms = set(_tokenize(text))
    overlap = len(query_terms & doc_terms)
    # Distance dominates, sparse signal assists, lexical overlap adds extra confidence.
    fused = dist - min(kw * 0.04, 0.2) - min(overlap * 0.05, 0.2)
    return (fused, dist)


def _cache_get(key: tuple[str, int, int, str, float, float]) -> list[tuple[str, float, float, float]] | None:
    hit = _RERANK_CACHE.get(key)
    if hit is None:
        return None
    _RERANK_CACHE.move_to_end(key)
    return hit


def _cache_set(key: tuple[str, int, int, str, float, float], value: list[tuple[str, float, float, float]]) -> None:
    _RERANK_CACHE[key] = value
    _RERANK_CACHE.move_to_end(key)
    while len(_RERANK_CACHE) > RERANK_CACHE_MAX:
        _RERANK_CACHE.popitem(last=False)


_doc_tokens = [_tokenize(text) for text in knowledge]
_doc_freq: dict[str, int] = {}
for tokens in _doc_tokens:
    for token in set(tokens):
        _doc_freq[token] = _doc_freq.get(token, 0) + 1

_avg_doc_len = (
    sum(len(tokens) for tokens in _doc_tokens) / len(_doc_tokens)
    if _doc_tokens
    else 1.0
)


def _get_cross_encoder() -> CrossEncoder | None:
    global _cross_encoder
    if _cross_encoder is not None:
        return _cross_encoder

    try:
        # Lightweight reranker suitable for short query-document pairs.
        _cross_encoder = CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2")
    except Exception:
        _cross_encoder = None
    return _cross_encoder


def _should_preload_reranker() -> bool:
    val = os.getenv("RERANK_PRELOAD", "1").strip().lower()
    return val in {"1", "true", "yes", "on"}


if _should_preload_reranker():
    _get_cross_encoder()


def retrieve(query: str, k: int = 3) -> list[str]:
    if not query.strip():
        return []

    k = max(1, min(k, len(knowledge)))
    query_vec = model.encode([query])
    query_vec = np.array(query_vec, dtype="float32")

    _distances, indices = index.search(query_vec, k)
    return [knowledge[i] for i in indices[0] if 0 <= i < len(knowledge)]


def retrieve_with_scores(query: str, k: int = 3) -> list[tuple[str, float]]:
    """Retrieve top-k knowledge chunks paired with L2 distance.

    Lower distance means higher similarity. Filtering/decision logic should
    be handled by the caller.
    """
    if not query.strip():
        return []

    k = max(1, min(k, len(knowledge)))
    query_vec = model.encode([query])
    query_vec = np.array(query_vec, dtype="float32")

    distances, indices = index.search(query_vec, k)

    results: list[tuple[str, float]] = []
    for dist, idx in zip(distances[0], indices[0]):
        i = int(idx)
        if 0 <= i < len(knowledge):
            results.append((knowledge[i], float(dist)))
    return results


def keyword_search(query: str, k: int = 5) -> list[tuple[str, float]]:
    """BM25-style sparse retrieval for typo/rare term resilience.

    Returns (chunk_text, keyword_score) sorted descending by relevance.
    """
    if not query.strip():
        return []

    query_tokens = _tokenize(query)
    if not query_tokens:
        return []

    query_terms = [term for term in query_tokens if term in _doc_freq]
    if not query_terms:
        return []

    n_docs = len(_doc_tokens)
    k1 = 1.5
    b = 0.75

    scores: list[tuple[str, float]] = []
    for i, doc_tokens in enumerate(_doc_tokens):
        if not doc_tokens:
            continue

        tf = Counter(doc_tokens)
        doc_len = len(doc_tokens)
        score = 0.0
        for term in query_terms:
            freq = tf.get(term, 0)
            if freq == 0:
                continue

            df = _doc_freq.get(term, 1)
            idf = math.log(((n_docs - df + 0.5) / (df + 0.5)) + 1.0)
            denom = freq + k1 * (1.0 - b + b * (doc_len / _avg_doc_len))
            score += idf * ((freq * (k1 + 1.0)) / denom)

        if score > 0.0:
            scores.append((knowledge[i], float(score)))

    scores.sort(key=lambda x: x[1], reverse=True)
    return scores[: max(1, k)]


def hybrid_retrieve(query: str, vector_k: int = 8, sparse_k: int = 8) -> list[tuple[str, float, float]]:
    """Run independent vector and sparse retrieval, then union candidates.

    Returns tuples of:
        (chunk_text, vector_distance, sparse_score)
    where missing signals are filled with sentinel values.
    """
    vector_results = retrieve_with_scores(query, k=vector_k)
    sparse_results = keyword_search(query, k=sparse_k)

    merged: dict[str, dict[str, float]] = {}

    for text, dist in vector_results:
        merged[text] = {"dist": float(dist), "kw": 0.0}

    for text, kw_score in sparse_results:
        if text not in merged:
            merged[text] = {"dist": float("inf"), "kw": float(kw_score)}
        else:
            merged[text]["kw"] = max(merged[text]["kw"], float(kw_score))

    return [(text, vals["dist"], vals["kw"]) for text, vals in merged.items()]


def fast_rank_hybrid_candidates(
    query: str,
    candidates: list[tuple[str, float, float]],
    top_k: int = 3,
) -> list[tuple[str, float, float, float]]:
    """Cheap ranking path used when retrieval signal is already strong.

    Returns tuples of:
        (chunk_text, vector_distance, sparse_score, rerank_score)
    where rerank_score is 0.0 because cross-encoder is skipped.
    """
    if not candidates:
        return []

    top_k = max(1, top_k)
    query_terms = set(_tokenize(query))
    ranked = sorted(candidates, key=lambda item: _cheap_fusion_score(query_terms, item))[:top_k]
    return [(text, dist, kw, 0.0) for text, dist, kw in ranked]


def _candidate_fingerprint(candidates: list[tuple[str, float, float]]) -> str:
    """Stable fingerprint of candidate content and coarse scores for cache keys."""
    payload_parts: list[str] = []
    for text, dist, kw in candidates:
        coarse_dist = "inf" if math.isinf(dist) else f"{dist:.3f}"
        payload_parts.append(f"{text}|d={coarse_dist}|k={kw:.3f}")
    payload = "\n".join(payload_parts)
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()[:16]


def rerank_hybrid_candidates(
    query: str,
    candidates: list[tuple[str, float, float]],
    top_k: int = 3,
    rerank_top: int = 5,
    max_rerank_sec: float = 1.5,
    early_stop_score: float = 8.0,
) -> list[tuple[str, float, float, float]]:
    """Rerank hybrid candidates with a cross-encoder when available.

    Returns tuples of:
        (chunk_text, vector_distance, sparse_score, rerank_score)
    """
    if not candidates:
        return []

    top_k = max(1, top_k)
    rerank_top = max(top_k, rerank_top)
    max_rerank_sec = max(0.2, float(max_rerank_sec))

    # Prefilter by a cheap fused score so cross-encoder only sees likely candidates.
    query_terms = set(_tokenize(query))
    prefiltered = sorted(candidates, key=lambda item: _cheap_fusion_score(query_terms, item))[:rerank_top]

    cache_key = (
        query.strip().lower(),
        top_k,
        rerank_top,
        _candidate_fingerprint(prefiltered),
        round(max_rerank_sec, 2),
        round(float(early_stop_score), 2),
    )
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached[:top_k]

    cross_encoder = _get_cross_encoder()

    if cross_encoder is None:
        # Fallback score when cross-encoder is not available.
        ranked = sorted(
            prefiltered,
            key=lambda item: _cheap_fusion_score(query_terms, item),
        )
        result = [(text, dist, kw, 0.0) for text, dist, kw in ranked[:top_k]]
        _cache_set(cache_key, result)
        return result

    # Evaluate candidates sequentially with per-candidate timeout to enforce time caps.
    enriched: list[tuple[str, float, float, float]] = []
    started_at = time.perf_counter()
    for text, dist, kw in prefiltered:
        elapsed = time.perf_counter() - started_at
        remaining = max_rerank_sec - elapsed
        if remaining <= 0.0:
            break

        executor: ThreadPoolExecutor | None = None
        try:
            executor = ThreadPoolExecutor(max_workers=1)
            future = executor.submit(cross_encoder.predict, [[query, text]])
            score = float(future.result(timeout=remaining)[0])
            executor.shutdown(wait=False, cancel_futures=True)
        except FutureTimeoutError:
            if executor is not None:
                executor.shutdown(wait=False, cancel_futures=True)
            break
        except Exception:
            if executor is not None:
                executor.shutdown(wait=False, cancel_futures=True)
            break
        enriched.append((text, dist, kw, score))
        if score >= early_stop_score:
            break

    if not enriched:
        ranked = sorted(
            prefiltered,
            key=lambda item: _cheap_fusion_score(query_terms, item),
        )
        result = [(text, dist, kw, 0.0) for text, dist, kw in ranked[:top_k]]
        _cache_set(cache_key, result)
        return result

    if len(enriched) < len(prefiltered):
        scored_texts = {text for text, _dist, _kw, _score in enriched}
        leftovers = [item for item in prefiltered if item[0] not in scored_texts]
        leftovers_sorted = sorted(leftovers, key=lambda item: _cheap_fusion_score(query_terms, item))
        enriched.extend((text, dist, kw, 0.0) for text, dist, kw in leftovers_sorted)

    enriched.sort(key=lambda item: item[3], reverse=True)

    # Diversity pass: avoid selecting near-duplicate chunks with identical wording.
    selected: list[tuple[str, float, float, float]] = []
    seen_terms: set[str] = set()
    for item in enriched:
        text, _dist, _kw, _score = item
        terms = set(_tokenize(text))
        overlap = len(terms & seen_terms)
        if selected and overlap > 12:
            continue
        selected.append(item)
        seen_terms.update(terms)
        if len(selected) >= top_k:
            break

    if len(selected) < top_k:
        for item in enriched:
            if item in selected:
                continue
            selected.append(item)
            if len(selected) >= top_k:
                break

    _cache_set(cache_key, selected)
    return selected

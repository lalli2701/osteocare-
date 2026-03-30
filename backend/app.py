import os
import logging
import time
import gzip
import threading
import random
import re
import html
import hmac
import hashlib
import base64
import uuid
from collections import OrderedDict
from urllib import request as urllib_request
from urllib import error as urllib_error
from dotenv import load_dotenv
import json
import joblib
import numpy as np
import pandas as pd
import sqlite3
from datetime import date, datetime, timedelta
from flask import Flask, jsonify, request, g
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
try:
    from pymongo import MongoClient
    from pymongo.errors import DuplicateKeyError
except Exception:
    MongoClient = None
    DuplicateKeyError = Exception

try:
    from google.cloud import translate_v2 as google_translate
except Exception:
    google_translate = None

# Import authentication module
from auth import init_auth_db, signup_user, login_user, token_required, get_user_by_id, decode_token

try:
    from chatbot import chatbot_response
except Exception:
    chatbot_response = None

# Load environment variables from backend/.env if present
load_dotenv()

# Paths for artifacts (place your saved model and feature list here)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def _resolve_path(path_val: str, default_rel: str) -> str:
    """Resolve artifact path to an absolute path under backend/ even if given relative."""
    if path_val:
        candidate = path_val
    else:
        candidate = default_rel
    if os.path.isabs(candidate):
        return candidate
    return os.path.join(BASE_DIR, candidate)


MODEL_PATH = _resolve_path(os.environ.get("MODEL_PATH", ""), os.path.join("artifacts", "calibrated_model.pkl"))
FEATURES_PATH = _resolve_path(os.environ.get("FEATURES_PATH", ""), os.path.join("artifacts", "feature_order.json"))
DB_PATH = _resolve_path(os.environ.get("USER_DB_PATH", ""), "users.db")
MONGO_URI = os.environ.get("MONGODB_URI", "").strip()
MONGO_DB_NAME = os.environ.get("MONGODB_DB_NAME", "osteocare")
MONGO_COLLECTION_NAME = os.environ.get("MONGODB_COLLECTION", "survey_submissions")
MONGO_REMINDER_CONFIG_COLLECTION_NAME = os.environ.get("MONGODB_REMINDER_CONFIG_COLLECTION", "reminder_config")
MONGO_REMINDER_HISTORY_COLLECTION_NAME = os.environ.get("MONGODB_REMINDER_HISTORY_COLLECTION", "reminder_history")
MODEL_VERSION = os.environ.get("MODEL_VERSION", "v1.0.0").strip() or "v1.0.0"
SYNC_SCHEMA_VERSION = int(os.environ.get("SYNC_SCHEMA_VERSION", "1"))
SYNC_RETENTION_DAYS = int(os.environ.get("SYNC_RETENTION_DAYS", "90"))
SYNC_SIGNING_SECRET = os.environ.get("SYNC_SIGNING_SECRET", "dev-sync-signing-key")
SYNC_SIGNING_KEYS_RAW = os.environ.get("SYNC_SIGNING_KEYS", "").strip()
SYNC_SIGNATURE_MAX_SKEW_SECONDS = int(os.environ.get("SYNC_SIGNATURE_MAX_SKEW_SECONDS", "300"))
SYNC_NONCE_CACHE_MAX_SIZE = int(os.environ.get("SYNC_NONCE_CACHE_MAX_SIZE", "50000"))
SYNC_ALERT_FAILURE_RATE = float(os.environ.get("SYNC_ALERT_FAILURE_RATE", "0.2"))
SYNC_ALERT_FAILURE_COUNT = int(os.environ.get("SYNC_ALERT_FAILURE_COUNT", "25"))
SYNC_ALERT_WEBHOOK_URL = os.environ.get("SYNC_ALERT_WEBHOOK_URL", "").strip()
SYNC_ALERT_WEBHOOK_URLS_RAW = os.environ.get("SYNC_ALERT_WEBHOOK_URLS", "").strip()
SYNC_ALERT_COOLDOWN_SECONDS = int(os.environ.get("SYNC_ALERT_COOLDOWN_SECONDS", "300"))
SYNC_ALERT_DELIVERY_RETRIES = int(os.environ.get("SYNC_ALERT_DELIVERY_RETRIES", "3"))
SYNC_BACKPRESSURE_REQUESTS_PER_MINUTE = int(os.environ.get("SYNC_BACKPRESSURE_REQUESTS_PER_MINUTE", "800"))
SYNC_BACKPRESSURE_FAILURE_RATE = float(os.environ.get("SYNC_BACKPRESSURE_FAILURE_RATE", "0.35"))
SYNC_BACKPRESSURE_RETRY_AFTER_SECONDS = int(os.environ.get("SYNC_BACKPRESSURE_RETRY_AFTER_SECONDS", "10"))
SYNC_LOAD_SHED_REQUESTS_PER_MINUTE = int(os.environ.get("SYNC_LOAD_SHED_REQUESTS_PER_MINUTE", "1200"))
SYNC_LOAD_SHED_RETRY_AFTER_SECONDS = int(os.environ.get("SYNC_LOAD_SHED_RETRY_AFTER_SECONDS", "15"))
SYNC_REQUIRE_DATA_HASH = os.environ.get("SYNC_REQUIRE_DATA_HASH", "1").strip() == "1"
SYNC_BACKUP_INTERVAL_MINUTES = int(os.environ.get("SYNC_BACKUP_INTERVAL_MINUTES", "0"))
SYNC_BACKUP_DIR = os.environ.get("SYNC_BACKUP_DIR", os.path.join(BASE_DIR, "logs", "backups"))
SYNC_BACKUP_CONSISTENCY_MODE = os.environ.get("SYNC_BACKUP_CONSISTENCY_MODE", "window").strip().lower() or "window"
ADMIN_EXPORT_TOKEN = os.environ.get("ADMIN_EXPORT_TOKEN", "").strip()
SYNC_CHAOS_FAIL_RATE = float(os.environ.get("SYNC_CHAOS_FAIL_RATE", "0.0"))
SYNC_CHAOS_DELAY_MS = int(os.environ.get("SYNC_CHAOS_DELAY_MS", "0"))
SYNC_CHAOS_MODE = os.environ.get("SYNC_CHAOS_MODE", "").strip().lower()
SYNC_CHAOS_MODE_RATE = float(os.environ.get("SYNC_CHAOS_MODE_RATE", "1.0"))
SYNC_CHAOS_PARTIAL_WRITE_DROP_RATE = float(os.environ.get("SYNC_CHAOS_PARTIAL_WRITE_DROP_RATE", "0.35"))
SYNC_GROUP_CONTRACT_SECRET = os.environ.get("SYNC_GROUP_CONTRACT_SECRET", SYNC_SIGNING_SECRET)
SYNC_GROUP_CONTRACT_TTL_SECONDS = int(os.environ.get("SYNC_GROUP_CONTRACT_TTL_SECONDS", "1800"))
SYNC_GROUP_MAX_EXPECTED_COUNT = int(os.environ.get("SYNC_GROUP_MAX_EXPECTED_COUNT", "100"))
SYNC_REQUIRE_GROUP_TOKEN = os.environ.get("SYNC_REQUIRE_GROUP_TOKEN", "1").strip() == "1"
SYNC_CURSOR_STATE_MAX_USERS = int(os.environ.get("SYNC_CURSOR_STATE_MAX_USERS", "50000"))
SYNC_CURSOR_ALERT_REGRESSION_RATE = float(os.environ.get("SYNC_CURSOR_ALERT_REGRESSION_RATE", "0.02"))
SYNC_CURSOR_ALERT_MIN_SUBMISSIONS = int(os.environ.get("SYNC_CURSOR_ALERT_MIN_SUBMISSIONS", "50"))
SYNC_CHAOS_GATE_MIN_SAMPLES = int(os.environ.get("SYNC_CHAOS_GATE_MIN_SAMPLES", "20"))
SYNC_CHAOS_GATE_MAX_SUCCESS_DROP = float(os.environ.get("SYNC_CHAOS_GATE_MAX_SUCCESS_DROP", "0.05"))
SYNC_CHAOS_GATE_MAX_LATENCY_INCREASE_RATIO = float(os.environ.get("SYNC_CHAOS_GATE_MAX_LATENCY_INCREASE_RATIO", "0.20"))
SYNC_PULL_DEFAULT_LIMIT = int(os.environ.get("SYNC_PULL_DEFAULT_LIMIT", "100"))
SYNC_PULL_MAX_LIMIT = int(os.environ.get("SYNC_PULL_MAX_LIMIT", "250"))
SYNC_PULL_MAX_RESPONSE_BYTES = int(os.environ.get("SYNC_PULL_MAX_RESPONSE_BYTES", "524288"))
SYNC_PULL_MAX_TIME_MS = int(os.environ.get("SYNC_PULL_MAX_TIME_MS", "5000"))
# MongoDB health check configuration
MONGODB_HEALTH_CHECK_INTERVAL_SECONDS = int(os.environ.get("MONGODB_HEALTH_CHECK_INTERVAL_SECONDS", "30"))
MONGODB_HEALTH_CHECK_ALERT_COOLDOWN_SECONDS = int(os.environ.get("MONGODB_HEALTH_CHECK_ALERT_COOLDOWN_SECONDS", "300"))
# MongoDB degraded mode & connection pool
MONGODB_DEGRADED_QUEUE_DB = os.environ.get("MONGODB_DEGRADED_QUEUE_DB", os.path.join(BASE_DIR, "degraded_queue.db"))
MONGODB_MAX_POOL_SIZE = int(os.environ.get("MONGODB_MAX_POOL_SIZE", "50"))
MONGODB_MIN_POOL_SIZE = int(os.environ.get("MONGODB_MIN_POOL_SIZE", "5"))
# Degraded mode safeguards: prevent queue explosion, flush storms, retry failures
MONGODB_DEGRADED_MAX_QUEUE_SIZE = int(os.environ.get("MONGODB_DEGRADED_MAX_QUEUE_SIZE", "10000"))
MONGODB_DEGRADED_FLUSH_BATCH_SIZE = int(os.environ.get("MONGODB_DEGRADED_FLUSH_BATCH_SIZE", "100"))
MONGODB_DEGRADED_FLUSH_BATCH_DELAY_SECONDS = float(os.environ.get("MONGODB_DEGRADED_FLUSH_BATCH_DELAY_SECONDS", "1.0"))
MONGODB_DEGRADED_MAX_RETRY_COUNT = int(os.environ.get("MONGODB_DEGRADED_MAX_RETRY_COUNT", "5"))
# Adaptive health check (fast when failed, slow when healthy)
MONGODB_HEALTH_CHECK_FAST_INTERVAL_SECONDS = int(os.environ.get("MONGODB_HEALTH_CHECK_FAST_INTERVAL_SECONDS", "5"))
MONGODB_HEALTH_CHECK_SLOW_INTERVAL_SECONDS = int(os.environ.get("MONGODB_HEALTH_CHECK_SLOW_INTERVAL_SECONDS", "60"))
# Dynamic translation configuration (Google Translate API)
GOOGLE_TRANSLATE_ENABLED = os.environ.get("GOOGLE_TRANSLATE_ENABLED", "1").strip() == "1"
GOOGLE_TRANSLATE_ALLOWED_LANGS = {
    item.strip().lower()
    for item in os.environ.get("GOOGLE_TRANSLATE_ALLOWED_LANGS", "en,hi,te").split(",")
    if item.strip()
}
GOOGLE_TRANSLATE_CACHE_TTL_SECONDS = int(os.environ.get("GOOGLE_TRANSLATE_CACHE_TTL_SECONDS", "86400"))
GOOGLE_TRANSLATE_CACHE_MAX_ENTRIES = int(os.environ.get("GOOGLE_TRANSLATE_CACHE_MAX_ENTRIES", "5000"))
# Set default dev API key for easy development
API_KEY = os.environ.get("API_KEY", "dev-key")

DAILY_PLAN_TASKS = [
    "Calcium intake (milk or equivalent)",
    "20 minutes sunlight",
    "Exercise / walk",
]

app = Flask(__name__)
CORS(app)

chat_monitor_logger = logging.getLogger("chat_monitor")
if not chat_monitor_logger.handlers:
    logs_dir = os.path.join(BASE_DIR, "logs")
    os.makedirs(logs_dir, exist_ok=True)

    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s"))
    chat_monitor_logger.addHandler(handler)

    file_handler = logging.FileHandler(os.path.join(logs_dir, "chat_monitor.log"), encoding="utf-8")
    file_handler.setFormatter(logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s"))
    chat_monitor_logger.addHandler(file_handler)
chat_monitor_logger.setLevel(logging.INFO)

sync_audit_logger = logging.getLogger("sync_audit")
if not sync_audit_logger.handlers:
    logs_dir = os.path.join(BASE_DIR, "logs")
    os.makedirs(logs_dir, exist_ok=True)

    audit_handler = logging.FileHandler(os.path.join(logs_dir, "sync_audit.log"), encoding="utf-8")
    audit_handler.setFormatter(logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s"))
    sync_audit_logger.addHandler(audit_handler)
sync_audit_logger.setLevel(logging.INFO)


def _rate_limit_key():
    user_id = request.headers.get("X-User-Id", "").strip()
    if user_id:
        return f"user:{user_id}"
    return get_remote_address()


limiter = Limiter(_rate_limit_key, app=app, default_limits=["100 per hour"])  # basic abuse guard

# Initialize authentication database
init_auth_db(DB_PATH)

_model = None
_feature_order: list[str] | None = None
_mongo_client = None
_mongo_collection = None
_mongo_reminder_config_collection = None
_mongo_reminder_history_collection = None
_sync_metrics = {
    "batch_requests": 0,
    "single_requests": 0,
    "status_checks": 0,
    "records_received": 0,
    "records_synced": 0,
    "records_failed": 0,
    "failure_reasons": {},
    "window_started_at": time.time(),
    "window_requests": 0,
    "cursor_submissions": 0,
    "cursor_regressions": 0,
}
_sync_nonce_cache: OrderedDict[str, float] = OrderedDict()
_sync_alert_state: dict[str, float] = {}
_sync_alert_active: dict[str, bool] = {}
_sync_backup_lock = threading.Lock()
_sync_writes_paused = False
_sync_cursor_state: OrderedDict[str, tuple[str, str]] = OrderedDict()
# MongoDB health check state
_mongo_health_lock = threading.Lock()
_mongo_health_status = {"connected": False, "last_check": 0.0, "last_alert": 0.0, "was_connected": False}
_mongo_health_check_thread = None
# MongoDB degraded mode state (when Mongo is down)
_mongo_degraded_mode = False
_mongo_degraded_queue_lock = threading.Lock()
# Alert state tracking (prevent spam)
_mongo_alert_state = {"last_down_alert_ts": 0.0, "last_recovery_alert_ts": 0.0, "is_in_down_state": False}
# Dynamic translation state
_google_translate_client = None
_google_translate_cache: OrderedDict[str, tuple[str, float]] = OrderedDict()
_google_translate_lock = threading.Lock()


def _parse_signing_keys() -> dict[str, str]:
    if not SYNC_SIGNING_KEYS_RAW:
        return {"1": SYNC_SIGNING_SECRET}

    parsed: dict[str, str] = {}
    chunks = [item.strip() for item in SYNC_SIGNING_KEYS_RAW.split(",") if item.strip()]
    for chunk in chunks:
        if ":" not in chunk:
            continue
        version, secret = chunk.split(":", 1)
        version = version.strip()
        secret = secret.strip()
        if version and secret:
            parsed[version] = secret

    if not parsed:
        parsed["1"] = SYNC_SIGNING_SECRET
    return parsed


SYNC_SIGNING_KEYS = _parse_signing_keys()


def _parse_webhook_targets() -> list[str]:
    urls: list[str] = []
    if SYNC_ALERT_WEBHOOK_URL:
        urls.append(SYNC_ALERT_WEBHOOK_URL)
    if SYNC_ALERT_WEBHOOK_URLS_RAW:
        urls.extend([u.strip() for u in SYNC_ALERT_WEBHOOK_URLS_RAW.split(",") if u.strip()])
    # Preserve order while deduplicating.
    seen = set()
    result = []
    for url in urls:
        if url in seen:
            continue
        seen.add(url)
        result.append(url)
    return result


SYNC_ALERT_WEBHOOK_TARGETS = _parse_webhook_targets()


def _is_sync_data_endpoint(path: str) -> bool:
    return path in {"/save", "/save/status", "/save/batch", "/sync/pull"}


def _chaos_mode_enabled(mode: str) -> bool:
    if not SYNC_CHAOS_MODE:
        return False
    modes = {item.strip() for item in SYNC_CHAOS_MODE.split(",") if item.strip()}
    return mode in modes


def _chaos_mode_triggered(mode: str) -> bool:
    if not _chaos_mode_enabled(mode):
        return False
    return random.random() < max(0.0, min(1.0, SYNC_CHAOS_MODE_RATE))


def _get_google_translate_client():
    global _google_translate_client
    if _google_translate_client is not None:
        return _google_translate_client
    if google_translate is None:
        return None
    try:
        _google_translate_client = google_translate.Client()
        return _google_translate_client
    except Exception as exc:
        app.logger.warning("Google Translate client unavailable: %s", exc)
        return None


def _translation_cache_get(cache_key: str) -> str | None:
    now_ts = time.time()
    with _google_translate_lock:
        item = _google_translate_cache.get(cache_key)
        if not item:
            return None
        value, expires_at = item
        if expires_at <= now_ts:
            _google_translate_cache.pop(cache_key, None)
            return None
        _google_translate_cache.move_to_end(cache_key)
        return value


def _translation_cache_set(cache_key: str, value: str):
    expires_at = time.time() + max(60, GOOGLE_TRANSLATE_CACHE_TTL_SECONDS)
    with _google_translate_lock:
        _google_translate_cache[cache_key] = (value, expires_at)
        _google_translate_cache.move_to_end(cache_key)
        while len(_google_translate_cache) > max(100, GOOGLE_TRANSLATE_CACHE_MAX_ENTRIES):
            _google_translate_cache.popitem(last=False)


def _translate_dynamic_text(text: str, target_lang: str) -> tuple[str, str]:
    """Translate dynamic text with cache and safe fallback.

    Returns tuple of (translated_text, source_tag), where source_tag is
    one of: passthrough, cache, google, fallback.
    """
    normalized_text = text.strip()
    normalized_lang = target_lang.strip().lower()

    if not normalized_text:
        return "", "passthrough"
    if normalized_lang == "en":
        return normalized_text, "passthrough"
    if GOOGLE_TRANSLATE_ALLOWED_LANGS and normalized_lang not in GOOGLE_TRANSLATE_ALLOWED_LANGS:
        return normalized_text, "passthrough"
    if not GOOGLE_TRANSLATE_ENABLED:
        return normalized_text, "passthrough"

    cache_key = f"{normalized_lang}|{normalized_text}"
    cached = _translation_cache_get(cache_key)
    if cached is not None:
        return cached, "cache"

    client = _get_google_translate_client()
    if client is None:
        return normalized_text, "fallback"

    try:
        result = client.translate(normalized_text, target_language=normalized_lang, format_="text")
        translated = str(result.get("translatedText") or normalized_text).strip()
        translated = html.unescape(translated)
        if not translated:
            translated = normalized_text
        _translation_cache_set(cache_key, translated)
        return translated, "google"
    except Exception as exc:
        app.logger.warning("Dynamic translation failed lang=%s: %s", normalized_lang, exc)
        return normalized_text, "fallback"


def _encode_group_contract_token(payload: dict) -> str:
    canonical = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    signature = hmac.new(
        SYNC_GROUP_CONTRACT_SECRET.encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    encoded_payload = base64.urlsafe_b64encode(canonical.encode("utf-8")).decode("ascii")
    return f"{encoded_payload}.{signature}"


def _decode_group_contract_token(token: str, user_id: str) -> tuple[dict | None, str]:
    if not isinstance(token, str) or "." not in token:
        return None, "invalid group token format"

    encoded_payload, provided_signature = token.rsplit(".", 1)
    try:
        canonical = base64.urlsafe_b64decode(encoded_payload.encode("ascii")).decode("utf-8")
    except Exception:
        return None, "invalid group token payload"

    expected_signature = hmac.new(
        SYNC_GROUP_CONTRACT_SECRET.encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(expected_signature, provided_signature):
        return None, "invalid group token signature"

    try:
        payload = json.loads(canonical)
    except Exception:
        return None, "invalid group token json"

    now_ts = int(time.time())
    expires_at = int(payload.get("exp", 0) or 0)
    if expires_at <= now_ts:
        return None, "group token expired"

    token_user = str(payload.get("uid", ""))
    if token_user != user_id:
        return None, "group token user mismatch"

    group_id = str(payload.get("gid", "")).strip()
    if not group_id:
        return None, "group token missing group id"

    expected_count = payload.get("ec")
    if not isinstance(expected_count, int) or expected_count < 1 or expected_count > SYNC_GROUP_MAX_EXPECTED_COUNT:
        return None, "group token expected_count invalid"

    group_version = payload.get("gv", 1)
    if not isinstance(group_version, int) or group_version < 1:
        return None, "group token group_version invalid"

    return {
        "sync_group_id": group_id,
        "sync_group_expected_count": expected_count,
        "sync_group_version": group_version,
        "issued_at": int(payload.get("iat", 0) or 0),
        "expires_at": expires_at,
    }, ""


def _extract_group_contract(payload: dict, user_id: str) -> tuple[dict | None, tuple | None]:
    token = payload.get("group_token")
    if token is None:
        if SYNC_REQUIRE_GROUP_TOKEN:
            return None, (jsonify({"error": "group_token is required"}), 400)
        return None, None

    if not isinstance(token, str) or not token.strip():
        return None, (jsonify({"error": "group_token must be a non-empty string"}), 400)

    decoded, err = _decode_group_contract_token(token.strip(), user_id)
    if decoded is None:
        return None, (jsonify({"error": err}), 400)
    return decoded, None


def _cursor_tuple(created_at: str, local_id: str) -> tuple[str, str]:
    return created_at, local_id


def _is_cursor_regression(user_id: str, created_at: str, local_id: str) -> bool:
    current = _sync_cursor_state.get(user_id)
    if current is None:
        return False
    return _cursor_tuple(created_at, local_id) < current


def _update_cursor_state(user_id: str, created_at: str, local_id: str):
    if not user_id or not created_at:
        return

    current = _sync_cursor_state.get(user_id)
    incoming = _cursor_tuple(created_at, local_id)
    if current is not None and incoming < current:
        return

    _sync_cursor_state[user_id] = incoming
    _sync_cursor_state.move_to_end(user_id)
    while len(_sync_cursor_state) > max(1000, SYNC_CURSOR_STATE_MAX_USERS):
        _sync_cursor_state.popitem(last=False)


def _evaluate_chaos_gate(
    min_samples: int,
    max_success_drop: float,
    max_latency_increase_ratio: float,
) -> dict:
    chaos_corr = _sync_metrics.get("chaos_correlation", {})
    chaos_requests = int(chaos_corr.get("chaos_requests", 0) or 0)
    baseline_requests = int(chaos_corr.get("non_chaos_requests", 0) or 0)
    chaos_success = int(chaos_corr.get("chaos_success", 0) or 0)
    baseline_success = int(chaos_corr.get("non_chaos_success", 0) or 0)
    chaos_latency_total = float(chaos_corr.get("chaos_latency_ms_total", 0.0) or 0.0)
    baseline_latency_total = float(chaos_corr.get("non_chaos_latency_ms_total", 0.0) or 0.0)

    result = {
        "passed": True,
        "reasons": [],
        "thresholds": {
            "min_samples": min_samples,
            "max_success_drop": max_success_drop,
            "max_latency_increase_ratio": max_latency_increase_ratio,
        },
        "samples": {
            "chaos_requests": chaos_requests,
            "baseline_requests": baseline_requests,
        },
    }

    if chaos_requests < min_samples or baseline_requests < min_samples:
        result["passed"] = False
        result["reasons"].append("insufficient_samples")
        return result

    chaos_success_rate = chaos_success / max(1, chaos_requests)
    baseline_success_rate = baseline_success / max(1, baseline_requests)
    success_drop = baseline_success_rate - chaos_success_rate

    chaos_latency_avg = chaos_latency_total / max(1, chaos_requests)
    baseline_latency_avg = baseline_latency_total / max(1, baseline_requests)
    latency_increase_ratio = 0.0
    if baseline_latency_avg > 0:
        latency_increase_ratio = (chaos_latency_avg - baseline_latency_avg) / baseline_latency_avg

    result["observed"] = {
        "chaos_success_rate": round(chaos_success_rate, 4),
        "baseline_success_rate": round(baseline_success_rate, 4),
        "success_drop": round(success_drop, 4),
        "chaos_latency_avg_ms": round(chaos_latency_avg, 2),
        "baseline_latency_avg_ms": round(baseline_latency_avg, 2),
        "latency_increase_ratio": round(latency_increase_ratio, 4),
    }

    if success_drop > max_success_drop:
        result["passed"] = False
        result["reasons"].append("success_drop_exceeded")
    if latency_increase_ratio > max_latency_increase_ratio:
        result["passed"] = False
        result["reasons"].append("latency_increase_exceeded")
    return result


def _extract_chat_question(payload: dict) -> str:
    message = str(payload.get("message", "")).strip()
    if message:
        return message

    messages = payload.get("messages")
    if isinstance(messages, list):
        for item in reversed(messages):
            if not isinstance(item, dict):
                continue
            if str(item.get("role", "")).lower() != "user":
                continue
            content = str(item.get("content", "")).strip()
            if content:
                return content

    return ""


def _extract_chat_history(payload: dict, max_items: int = 6) -> list[dict[str, str]]:
    messages = payload.get("messages")
    if not isinstance(messages, list):
        return []

    normalized: list[dict[str, str]] = []
    for item in messages:
        if not isinstance(item, dict):
            continue
        role = str(item.get("role", "")).strip().lower()
        content = str(item.get("content", "")).strip()
        if role not in {"user", "assistant"} or not content:
            continue
        normalized.append({"role": role, "content": content})

    return normalized[-max_items:]


def _get_mongo_collection():
    global _mongo_client, _mongo_collection
    if _mongo_collection is not None:
        return _mongo_collection
    if not MONGO_URI or MongoClient is None:
        app.logger.warning("🔴 MongoDB UNAVAILABLE: MONGO_URI=%s, MongoClient=%s", MONGO_URI or "NOT_SET", MongoClient)
        return None

    try:
        # Initialize with connection pool sizing to prevent exhaustion
        app.logger.info("🔗 Connecting to MongoDB at URI: %s", MONGO_URI[:50] + "..." if len(MONGO_URI) > 50 else MONGO_URI)
        _mongo_client = MongoClient(
            MONGO_URI, 
            serverSelectionTimeoutMS=2000,
            maxPoolSize=MONGODB_MAX_POOL_SIZE,
            minPoolSize=MONGODB_MIN_POOL_SIZE,
        )
        # Trigger an early connectivity check so failures are visible in logs.
        _mongo_client.admin.command("ping")
        app.logger.info("✅ MongoDB connection successful")
        app.logger.info("✅ MongoDB connection successful")
        _mongo_collection = _mongo_client[MONGO_DB_NAME][MONGO_COLLECTION_NAME]
        _mongo_collection.create_index(
            [("user_id", 1), ("local_id", 1)],
            unique=True,
            sparse=True,
            name="idx_user_local_id_unique",
        )
        _mongo_collection.create_index(
            [("server_created_at_dt", 1)],
            expireAfterSeconds=max(1, SYNC_RETENTION_DAYS) * 24 * 60 * 60,
            name="idx_sync_retention_ttl",
        )
        app.logger.info(
            "✅ MongoDB collection ready: db=%s collection=%s",
            MONGO_DB_NAME,
            MONGO_COLLECTION_NAME,
        )
        return _mongo_collection
    except Exception as exc:
        app.logger.error("❌ MongoDB connection FAILED: %s", exc)
        _mongo_client = None
        _mongo_collection = None
        return None


def _mongo_is_connected() -> bool:
    """Check MongoDB connectivity with real operation verification (not just ping).
    
    Tests actual query capability via find_one() to ensure DB is not just reachable
    but also responsive for real workloads. Returns cached status from periodic check.
    """
    with _mongo_health_lock:
        return _mongo_health_status.get("connected", False)


def _mongo_health_check_once() -> bool:
    """Perform actual operation test (find_one) to verify MongoDB is operational.
    
    Returns True if query succeeds, False otherwise. This is called periodically
    by the background health check thread.
    """
    collection = _get_mongo_collection()
    if collection is None or _mongo_client is None:
        return False
    try:
        # Test with real query: find_one with projection
        # More representative of actual workload than just ping
        collection.find_one({}, {"_id": 1})
        # If we got here, DB is reachable AND queryable
        return True
    except Exception:
        return False


def _run_mongodb_health_check():
    """Background thread that periodically checks MongoDB health.
    
    - Uses adaptive intervals: fast (5s) when degraded, slow (60s) when healthy
    - Detects state transitions (connected → disconnected)
    - Manages degraded mode (queuing writes locally)
    - Triggers alert webhook on state changes (not every check)
    - Only runs in main Flask worker (prevents multi-thread duplication)
    """
    while True:
        try:
            # Perform health check
            now_connected = _mongo_health_check_once()
            now_ts = time.time()
            global _mongo_degraded_mode
            
            with _mongo_health_lock:
                was_connected = _mongo_health_status.get("was_connected", False)
                
                # Update health status
                _mongo_health_status["connected"] = now_connected
                _mongo_health_status["last_check"] = now_ts
                
                # STATE TRANSITION: True → False (DISCONNECTION)
                if was_connected and not now_connected:
                    app.logger.error("MongoDB health check: DISCONNECTED (was connected)")
                    _mongo_degraded_mode = True
                    
                    # Trigger alert only once per disconnection (state-based dedup)
                    with _mongo_health_lock:
                        if not _mongo_alert_state.get("is_in_down_state", False):
                            _mongo_alert_state["is_in_down_state"] = True
                            _mongo_alert_state["last_down_alert_ts"] = now_ts
                            
                            alert_payload = {
                                "type": "mongodb_down",
                                "severity": "critical",
                                "timestamp": now_ts,
                                "message": f"MongoDB DISCONNECTED - entering degraded mode (db={MONGO_DB_NAME})",
                                "details": {
                                    "db": MONGO_DB_NAME,
                                    "collection": MONGO_COLLECTION_NAME,
                                    "degraded_mode_enabled": True,
                                }
                            }
                            _send_webhook_alert(alert_payload)
                
                # STATE TRANSITION: False → True (RECONNECTION)
                elif not was_connected and now_connected:
                    app.logger.info("MongoDB health check: RECONNECTED")
                    old_degraded_mode = _mongo_degraded_mode
                    _mongo_degraded_mode = False
                    
                    # Trigger recovery alert only once (state-based dedup)
                    if old_degraded_mode and _mongo_alert_state.get("is_in_down_state", False):
                        _mongo_alert_state["is_in_down_state"] = False
                        _mongo_alert_state["last_recovery_alert_ts"] = now_ts
                        
                        alert_payload = {
                            "type": "mongodb_recovered",
                            "severity": "info",
                            "timestamp": now_ts,
                            "message": f"MongoDB RECOVERED - exiting degraded mode (db={MONGO_DB_NAME})",
                            "details": {
                                "db": MONGO_DB_NAME,
                                "collection": MONGO_COLLECTION_NAME,
                                "degraded_mode_enabled": False,
                            }
                        }
                        _send_webhook_alert(alert_payload)
                        
                        # Attempt to flush queued writes
                        _flush_degraded_queue()
                
                # Update was_connected for next iteration
                _mongo_health_status["was_connected"] = now_connected
            
            # ADAPTIVE INTERVAL: Fast when degraded, slow when healthy
            sleep_interval = MONGODB_HEALTH_CHECK_FAST_INTERVAL_SECONDS if _mongo_degraded_mode else MONGODB_HEALTH_CHECK_SLOW_INTERVAL_SECONDS
            time.sleep(sleep_interval)
            
        except Exception as exc:
            app.logger.error("MongoDB health check thread error: %s", exc)
            time.sleep(MONGODB_HEALTH_CHECK_FAST_INTERVAL_SECONDS)


def _init_degraded_queue_db():
    """Initialize SQLite database for queueing writes when Mongo is down.
    
    Schema includes:
    - status: QUEUED, IN_PROGRESS, FAILED (for partial flush tracking)
    - error_message: Last error encountered (for debugging)
    - retry_count: Number of failed attempts (for giving up after max retries)
    
    Handles schema migrations from older versions.
    """
    try:
        conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
        
        # Check if table exists and has all columns
        cursor = conn.execute("PRAGMA table_info(degraded_queue)")
        columns = {row[1] for row in cursor.fetchall()}
        
        # Create or migrate table
        if "degraded_queue" not in [row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")]:
            # New table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS degraded_queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    operation_type TEXT NOT NULL,
                    collection_name TEXT NOT NULL,
                    document BLOB NOT NULL,
                    created_at REAL NOT NULL,
                    status TEXT DEFAULT 'QUEUED',
                    retry_count INTEGER DEFAULT 0,
                    error_message TEXT
                )
            """)
        else:
            # Existing table - migrate if needed
            if "status" not in columns:
                conn.execute("ALTER TABLE degraded_queue ADD COLUMN status TEXT DEFAULT 'QUEUED'")
                app.logger.info("Migrated degraded_queue: added status column")
            if "error_message" not in columns:
                conn.execute("ALTER TABLE degraded_queue ADD COLUMN error_message TEXT")
                app.logger.info("Migrated degraded_queue: added error_message column")
        
        # Create indexes
        conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_created_at ON degraded_queue(created_at)
        """)
        conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_status ON degraded_queue(status)
        """)
        conn.commit()
        conn.close()
        app.logger.info("Degraded mode queue database initialized/migrated: %s", MONGODB_DEGRADED_QUEUE_DB)
    except Exception as e:
        app.logger.error("Failed to initialize degraded queue: %s", e)


def _get_degraded_queue_size() -> int:
    """Get current number of queued operations."""
    try:
        with _mongo_degraded_queue_lock:
            conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
            cursor = conn.execute("SELECT COUNT(*) FROM degraded_queue WHERE status = 'QUEUED'")
            count = cursor.fetchone()[0]
            conn.close()
            return count
    except Exception as e:
        app.logger.error("Failed to get queue size: %s", e)
        return 0


def _queue_write_operation(operation_type: str, collection_name: str, document: dict) -> bool:
    """Queue a write operation locally when MongoDB is degraded.
    
    Safeguards:
    - BACKPRESSURE: Reject if queue exceeds MONGODB_DEGRADED_MAX_QUEUE_SIZE
    - STATUS TRACKING: Mark as QUEUED for proper flush tracking
    
    Args:
        operation_type: 'insert', 'update', 'delete'
        collection_name: Name of the collection
        document: The document to write
        
    Returns:
        True if queued successfully, False otherwise (queue full, backpressure).
    """
    try:
        with _mongo_degraded_queue_lock:
            # SAFEGUARD 1: Check queue size (prevent unbounded growth)
            conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
            cursor = conn.execute("SELECT COUNT(*) FROM degraded_queue WHERE status = 'QUEUED'")
            queue_size = cursor.fetchone()[0]
            
            if queue_size >= MONGODB_DEGRADED_MAX_QUEUE_SIZE:
                app.logger.warning(
                    "Degraded queue is full (%d >= %d), rejecting write operation",
                    queue_size, MONGODB_DEGRADED_MAX_QUEUE_SIZE
                )
                conn.close()
                return False
            
            # Log warning at 80% capacity
            if queue_size >= int(MONGODB_DEGRADED_MAX_QUEUE_SIZE * 0.8):
                app.logger.warning(
                    "Degraded queue approaching capacity: %d/%d (%.0f%%)",
                    queue_size, MONGODB_DEGRADED_MAX_QUEUE_SIZE,
                    (queue_size / MONGODB_DEGRADED_MAX_QUEUE_SIZE) * 100
                )
            
            # Queue the operation with QUEUED status
            doc_json = json.dumps(document)
            conn.execute(
                """INSERT INTO degraded_queue 
                   (operation_type, collection_name, document, created_at, status)
                   VALUES (?, ?, ?, ?, 'QUEUED')""",
                (operation_type, collection_name, doc_json, time.time())
            )
            conn.commit()
            conn.close()
        
        app.logger.debug("Queued %s operation for %s in degraded mode (size: %d/%d)", 
                        operation_type, collection_name, queue_size, MONGODB_DEGRADED_MAX_QUEUE_SIZE)
        return True
        
    except Exception as e:
        app.logger.error("Failed to queue write operation: %s", e)
        return False
        return False


def _flush_degraded_queue():
    """Attempt to flush queued writes to MongoDB now that it's recovered.
    
    Safeguards:
    - CONTROLLED FLUSH RATE: Process MONGODB_DEGRADED_FLUSH_BATCH_SIZE at a time
    - THROTTLE RECOVERY: Add MONGODB_DEGRADED_FLUSH_BATCH_DELAY_SECONDS between batches
    - PARTIAL FAILURE TRACKING: Mark records IN_PROGRESS, only delete on success
    - RETRY LOGIC: Track per-record failures, skip if exceeded max retries
    
    Returns early if MongoDB goes down mid-flush, preserving retry counts.
    """
    try:
        while True:
            with _mongo_degraded_queue_lock:
                conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
                
                # Fetch next batch of QUEUED operations (not IN_PROGRESS or FAILED retries)
                cursor = conn.execute("""
                    SELECT id, operation_type, collection_name, document
                    FROM degraded_queue
                    WHERE status = 'QUEUED' AND retry_count < ?
                    ORDER BY created_at ASC
                    LIMIT ?
                """, (MONGODB_DEGRADED_MAX_RETRY_COUNT, MONGODB_DEGRADED_FLUSH_BATCH_SIZE))
                
                rows = cursor.fetchall()
                
                if not rows:
                    # No more records to flush
                    conn.close()
                    break
                
                # SAFEGUARD: Mark batch as IN_PROGRESS (for partial failure tracking)
                row_ids = [row[0] for row in rows]
                placeholders = ",".join("?" * len(row_ids))
                conn.execute(f"""
                    UPDATE degraded_queue 
                    SET status = 'IN_PROGRESS' 
                    WHERE id IN ({placeholders})
                """, row_ids)
                conn.commit()
                conn.close()
            
            # Process this batch
            successful_ids = []
            failed_ids = []
            
            for row_id, op_type, coll_name, doc_json in rows:
                try:
                    # Get collection
                    if coll_name == "survey_submissions":
                        collection = _get_mongo_collection()
                    elif coll_name == "reminder_config":
                        collection = _get_mongo_reminder_config_collection()
                    elif coll_name == "reminder_history":
                        collection = _get_mongo_reminder_history_collection()
                    else:
                        app.logger.warning("Unknown collection in queue: %s", coll_name)
                        failed_ids.append((row_id, "Unknown collection"))
                        continue
                    
                    if collection is None:
                        # Mongo went down mid-flush, break and retry later
                        app.logger.warning("MongoDB became unavailable during flush, pausing...")
                        failed_ids.append((row_id, "MongoDB unavailable"))
                        break
                    
                    doc = json.loads(doc_json)
                    
                    # Execute operation
                    if op_type == "insert":
                        collection.insert_one(doc)
                    elif op_type == "update":
                        doc_id = doc.get("_id")
                        if doc_id:
                            collection.update_one({"_id": doc_id}, {"$set": doc})
                        else:
                            raise ValueError("Update operation missing _id")
                    elif op_type == "delete":
                        doc_id = doc.get("_id")
                        if doc_id:
                            collection.delete_one({"_id": doc_id})
                        else:
                            raise ValueError("Delete operation missing _id")
                    
                    successful_ids.append(row_id)
                    app.logger.debug("Flushed %s operation (id=%d) for %s", op_type, row_id, coll_name)
                    
                except Exception as e:
                    failed_ids.append((row_id, str(e)))
                    app.logger.warning("Failed to flush operation %d: %s", row_id, e)
            
            # SAFEGUARD: Update database with per-record results
            with _mongo_degraded_queue_lock:
                conn = sqlite3.connect(MONGODB_DEGRADED_QUEUE_DB)
                
                # Delete successfully flushed operations
                if successful_ids:
                    placeholders = ",".join("?" * len(successful_ids))
                    conn.execute(f"DELETE FROM degraded_queue WHERE id IN ({placeholders})", successful_ids)
                    app.logger.info("Flushed %d queued operations successfully", len(successful_ids))
                
                # Update failed operations: increment retry_count, update error_message, reset status to QUEUED
                for row_id, error_msg in failed_ids:
                    conn.execute("""
                        UPDATE degraded_queue 
                        SET status = 'QUEUED', retry_count = retry_count + 1, error_message = ?
                        WHERE id = ?
                    """, (error_msg, row_id))
                
                # Mark operations that exceeded max retry as FAILED (give up)
                conn.execute("""
                    UPDATE degraded_queue
                    SET status = 'FAILED'
                    WHERE retry_count >= ? AND status != 'FAILED'
                """, (MONGODB_DEGRADED_MAX_RETRY_COUNT,))
                
                conn.commit()
                conn.close()
            
            # If MongoDB became unavailable mid-flush, stop and let health check detect
            if not successful_ids and failed_ids:
                app.logger.warning("Flush stalled (all operations failed), MongoDB may be down again")
                break
            
            # SAFEGUARD: Throttle flush rate to prevent recovery storm
            if successful_ids:  # Only delay if we made progress
                app.logger.debug("Flushed batch, waiting %.1f seconds before next batch...", 
                                MONGODB_DEGRADED_FLUSH_BATCH_DELAY_SECONDS)
                time.sleep(MONGODB_DEGRADED_FLUSH_BATCH_DELAY_SECONDS)
            else:
                # No progress made, exit loop
                break
            
    except Exception as e:
        app.logger.error("Failed to flush degraded queue: %s", e)


def _start_mongodb_health_check():
    """Start background MongoDB health check thread at app startup.
    
    Only runs in the main Flask worker (prevents multi-worker duplication).
    Uses WERKZEUG_RUN_MAIN environment variable that Flask sets when running
    the main process (not in reloader or worker spawned processes).
    """
    global _mongo_health_check_thread
    
    if _mongo_health_check_thread is not None:
        return  # Already running
    
    if not MONGO_URI:
        app.logger.warning("MongoDB health check not started: MONGODB_URI is not set")
        return
    
    # IMPORTANT: Only run in main worker to prevent multi-worker duplication
    # WERKZEUG_RUN_MAIN is set by Flask only in the main process
    if os.environ.get("WERKZEUG_RUN_MAIN") != "true":
        app.logger.info("MongoDB health check skipped (not in main worker - likely multi-worker environment)")
        return
    
    # Daemon thread so it doesn't block app shutdown
    _mongo_health_check_thread = threading.Thread(target=_run_mongodb_health_check, daemon=True)
    _mongo_health_check_thread.start()
    app.logger.info("MongoDB health check thread started (fast=%s, slow=%s seconds)", 
                    MONGODB_HEALTH_CHECK_FAST_INTERVAL_SECONDS,
                    MONGODB_HEALTH_CHECK_SLOW_INTERVAL_SECONDS)


def _verify_mongodb_connection() -> bool:
    """Direct MongoDB connection verification at startup.
    
    Attempts immediate connection to MongoDB with 3-second timeout.
    Prints clear ✅/❌ feedback for developers.
    
    Returns:
        True if connection successful, False otherwise.
        Does NOT block app startup even if connection fails.
    """
    if not MONGO_URI:
        msg = "❌ MongoDB verification skipped: MONGODB_URI not set"
        print(msg)
        app.logger.warning(msg)
        return False
    
    try:
        # Direct connection attempt with aggressive timeout
        client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=3000)
        client.admin.command('ping')
        
        # If we got here, connection actually works
        msg = "✅ MongoDB CONNECTED (verified at startup)"
        print(msg)
        app.logger.info(msg)
        return True
        
    except Exception as e:
        msg = f"❌ MongoDB NOT CONNECTED: {e}"
        print(msg)
        app.logger.error(msg)
        return False


def _log_mongo_startup_status():
    if not MONGO_URI:
        app.logger.warning("MongoDB startup check: MONGODB_URI is not set")
        return

    connected = _mongo_is_connected()
    if connected:
        app.logger.info(
            "MongoDB startup check: CONNECTED db=%s collection=%s",
            MONGO_DB_NAME,
            MONGO_COLLECTION_NAME,
        )
    else:
        app.logger.warning(
            "MongoDB startup check: DISCONNECTED db=%s collection=%s",
            MONGO_DB_NAME,
            MONGO_COLLECTION_NAME,
        )


def _upsert_mongo_submission(user_id: str, local_id: str | None, document: dict) -> bool:
    collection = _get_mongo_collection()
    if collection is None:
        # 🔴 CRITICAL FIX: Queue write when MongoDB is unavailable
        app.logger.warning("⚠️ MongoDB unavailable → writing survey to degraded queue")
        
        # Queue the submission for later replay when Mongo recovers
        success = _queue_write_operation(
            operation_type="insert",
            collection_name="survey_submissions",
            document=document
        )
        
        if success:
            app.logger.info("✅ Survey queued in degraded mode for user_id=%s", user_id)
            return True
        else:
            app.logger.error("❌ Failed to queue survey (degraded queue full or error)")
            return False

    try:
        now_dt = datetime.utcnow()
        now_iso = now_dt.isoformat()

        if local_id:
            existing = collection.find_one(
                {"user_id": user_id, "local_id": local_id},
                {"_id": 1},
            )
            if existing:
                collection.update_one(
                    {"_id": existing["_id"]},
                    {
                        "$set": {
                            "server_updated_at": now_iso,
                            "last_seen_at": now_iso,
                        }
                    },
                )
                return True

            collection.insert_one({
                **document,
                "server_created_at": now_iso,
                "server_updated_at": now_iso,
                "server_created_at_dt": now_dt,
            })
        else:
            collection.insert_one({
                **document,
                "server_created_at": now_iso,
                "server_updated_at": now_iso,
                "server_created_at_dt": now_dt,
            })
        return True
    except DuplicateKeyError:
        # A newer record may already exist with the same idempotency key.
        if local_id:
            collection.update_one(
                {"user_id": user_id, "local_id": local_id},
                {"$set": {"last_seen_at": datetime.utcnow().isoformat()}},
            )
        return True
    except Exception as exc:
        app.logger.warning("MongoDB upsert failed: %s", exc)
        return False


def _get_mongo_reminder_config_collection():
    global _mongo_reminder_config_collection
    if _mongo_reminder_config_collection is not None:
        return _mongo_reminder_config_collection

    if _get_mongo_collection() is None or _mongo_client is None:
        return None

    try:
        _mongo_reminder_config_collection = _mongo_client[MONGO_DB_NAME][MONGO_REMINDER_CONFIG_COLLECTION_NAME]
        _mongo_reminder_config_collection.create_index(
            [("user_id", 1)],
            unique=True,
            name="idx_reminder_config_user_unique",
        )
        return _mongo_reminder_config_collection
    except Exception as exc:
        app.logger.warning("Reminder config collection unavailable: %s", exc)
        _mongo_reminder_config_collection = None
        return None


def _get_mongo_reminder_history_collection():
    global _mongo_reminder_history_collection
    if _mongo_reminder_history_collection is not None:
        return _mongo_reminder_history_collection

    if _get_mongo_collection() is None or _mongo_client is None:
        return None

    try:
        _mongo_reminder_history_collection = _mongo_client[MONGO_DB_NAME][MONGO_REMINDER_HISTORY_COLLECTION_NAME]
        _mongo_reminder_history_collection.create_index(
            [("user_id", 1), ("date", -1)],
            name="idx_reminder_history_user_date",
        )
        return _mongo_reminder_history_collection
    except Exception as exc:
        app.logger.warning("Reminder history collection unavailable: %s", exc)
        _mongo_reminder_history_collection = None
        return None


def _is_valid_reminder_time(value: str) -> bool:
    if not isinstance(value, str):
        return False
    return bool(re.match(r"^([01]\d|2[0-3]):([0-5]\d)$", value.strip()))


def _normalize_risk_level(value: str) -> str:
    level = str(value or "").strip().upper()
    if level in {"LOW", "MODERATE", "HIGH"}:
        return level
    return "MODERATE"


def _record_sync_failure(reason: str):
    reason_key = (reason or "unknown").strip()[:120]
    _sync_metrics["records_failed"] += 1
    _sync_metrics["failure_reasons"][reason_key] = _sync_metrics["failure_reasons"].get(reason_key, 0) + 1
    _send_sync_alerts_if_needed()


def _tick_request_window():
    now = time.time()
    window_started_at = float(_sync_metrics.get("window_started_at", now))
    if now - window_started_at >= 60:
        _sync_metrics["window_started_at"] = now
        _sync_metrics["window_requests"] = 0
    _sync_metrics["window_requests"] = int(_sync_metrics.get("window_requests", 0)) + 1


def _prune_old_nonces(now_ts: float):
    cutoff = now_ts - SYNC_SIGNATURE_MAX_SKEW_SECONDS
    while _sync_nonce_cache:
        first_nonce, first_seen_at = next(iter(_sync_nonce_cache.items()))
        if first_seen_at >= cutoff:
            break
        _sync_nonce_cache.pop(first_nonce, None)


def _retention_cutoff_dt() -> datetime:
    return datetime.utcnow() - timedelta(days=max(1, SYNC_RETENTION_DAYS))


def _verify_data_hash(record: dict) -> tuple[bool, str]:
    data_hash = record.get("data_hash")
    if not data_hash:
        if SYNC_REQUIRE_DATA_HASH:
            return False, "data_hash is required"
        return True, ""
    if not isinstance(data_hash, str) or len(data_hash.strip()) != 64:
        return False, "data_hash must be a 64-char SHA256 hex string"

    canonical_payload = {
        "local_id": record.get("local_id"),
        "timestamp": record.get("timestamp"),
        "schema_version": record.get("schema_version", 1),
        "survey_data": record.get("survey_data"),
    }
    canonical_json = json.dumps(canonical_payload, separators=(",", ":"), ensure_ascii=False)
    expected = hashlib.sha256(canonical_json.encode("utf-8")).hexdigest()
    if expected != data_hash.lower().strip():
        return False, "data_hash mismatch"
    return True, ""


def _should_apply_backpressure() -> tuple[bool, int]:
    window_requests = int(_sync_metrics.get("window_requests", 0))
    total = int(_sync_metrics.get("records_received", 0))
    failed = int(_sync_metrics.get("records_failed", 0))
    failure_rate = (failed / total) if total > 0 else 0.0

    if window_requests >= SYNC_BACKPRESSURE_REQUESTS_PER_MINUTE:
        return True, SYNC_BACKPRESSURE_RETRY_AFTER_SECONDS
    if failure_rate >= SYNC_BACKPRESSURE_FAILURE_RATE and total >= 20:
        return True, SYNC_BACKPRESSURE_RETRY_AFTER_SECONDS
    return False, 0


def _canonical_record_for_hash(record: dict) -> dict:
    return {
        "local_id": record.get("local_id"),
        "timestamp": record.get("timestamp"),
        "schema_version": record.get("schema_version", 1),
        "survey_data": record.get("survey_data"),
        "data_hash": record.get("data_hash"),
    }


def _verify_batch_hash(records: list[dict], batch_hash: str | None) -> tuple[bool, str]:
    if not batch_hash:
        if SYNC_REQUIRE_DATA_HASH:
            return False, "batch_hash is required"
        return True, ""

    if not isinstance(batch_hash, str) or len(batch_hash.strip()) != 64:
        return False, "batch_hash must be a 64-char SHA256 hex string"

    canonical_records = [_canonical_record_for_hash(record) for record in records]
    canonical_json = json.dumps(canonical_records, separators=(",", ":"), ensure_ascii=False)
    expected = hashlib.sha256(canonical_json.encode("utf-8")).hexdigest()
    if expected != batch_hash.lower().strip():
        return False, "batch_hash mismatch"
    return True, ""


def _require_admin_export_access():
    key_err = _require_api_key()
    if key_err:
        return key_err

    if not ADMIN_EXPORT_TOKEN:
        return jsonify({"error": "Admin export token not configured"}), 503

    supplied = request.headers.get("X-Admin-Token", "").strip()
    if supplied != ADMIN_EXPORT_TOKEN:
        return jsonify({"error": "Forbidden"}), 403
    return None


def _audit_sync_event(action: str, details: dict):
    ip = get_remote_address()
    entry = {
        "action": action,
        "ip": ip,
        "details": details,
    }
    sync_audit_logger.info(json.dumps(entry, ensure_ascii=False))


def _build_sync_backup_snapshot(days: int) -> dict:
    collection = _get_mongo_collection()
    if collection is None:
        raise RuntimeError("MongoDB unavailable")

    global _sync_writes_paused
    cutoff = datetime.utcnow() - timedelta(days=days)

    with _sync_backup_lock:
        if SYNC_BACKUP_CONSISTENCY_MODE == "pause_writes":
            _sync_writes_paused = True

        try:
            # Capture a stable upper bound so writes arriving during backup are
            # excluded from this snapshot and included in the next one.
            snapshot_upper_bound = datetime.utcnow()
            query = {
                "server_created_at_dt": {
                    "$gte": cutoff,
                    "$lte": snapshot_upper_bound,
                }
            }
            records = list(
                collection.find(query, {"_id": 0}).sort([
                    ("server_created_at", 1),
                    ("local_id", 1),
                ])
            )

            # Logical-group mode ensures related records are either all included
            # or all deferred, avoiding incomplete restores for grouped writes.
            excluded_groups: list[str] = []
            if SYNC_BACKUP_CONSISTENCY_MODE == "logical_group":
                grouped_candidates = {
                    str(record.get("sync_group_id"))
                    for record in records
                    if isinstance(record.get("sync_group_id"), str) and record.get("sync_group_id", "").strip()
                }

                expanded_group_records: dict[str, list[dict]] = {}
                complete_groups: set[str] = set()
                for group_id in grouped_candidates:
                    all_group_rows = list(
                        collection.find(
                            {
                                "sync_group_id": group_id,
                                "server_created_at_dt": {"$lte": snapshot_upper_bound},
                            },
                            {"_id": 0},
                        ).sort([
                            ("server_created_at", 1),
                            ("local_id", 1),
                        ])
                    )
                    if not all_group_rows:
                        continue

                    expected_candidates = [
                        int(r.get("sync_group_expected_count"))
                        for r in all_group_rows
                        if isinstance(r.get("sync_group_expected_count"), int) and int(r.get("sync_group_expected_count")) > 0
                    ]
                    expected_count = max(expected_candidates) if expected_candidates else 1
                    if len(all_group_rows) >= expected_count:
                        complete_groups.add(group_id)
                        expanded_group_records[group_id] = all_group_rows
                    else:
                        excluded_groups.append(group_id)

                base_non_group = [
                    r for r in records
                    if not (isinstance(r.get("sync_group_id"), str) and r.get("sync_group_id", "").strip())
                ]
                merged: list[dict] = base_non_group
                for gid in sorted(complete_groups):
                    merged.extend(expanded_group_records.get(gid, []))

                deduped: OrderedDict[tuple[str, str, str, str], dict] = OrderedDict()
                for row in merged:
                    k_user = str(row.get("user_id", ""))
                    k_local = str(row.get("local_id", ""))
                    k_created = str(row.get("server_created_at", ""))
                    k_source = str(row.get("source", ""))
                    deduped[(k_user, k_local, k_created, k_source)] = row
                records = list(deduped.values())
                records.sort(key=lambda r: (str(r.get("server_created_at", "")), str(r.get("local_id", ""))))
        finally:
            if SYNC_BACKUP_CONSISTENCY_MODE == "pause_writes":
                _sync_writes_paused = False

    return {
        "exported_at": datetime.utcnow().isoformat(),
        "days": days,
        "consistency_mode": SYNC_BACKUP_CONSISTENCY_MODE,
        "window_start": cutoff.isoformat(),
        "window_end": snapshot_upper_bound.isoformat(),
        "logical_groups_excluded": excluded_groups if SYNC_BACKUP_CONSISTENCY_MODE == "logical_group" else [],
        "count": len(records),
        "records": records,
    }


def _run_sync_backup_to_file(days: int | None = None) -> str:
    effective_days = max(1, days or max(1, SYNC_RETENTION_DAYS))
    snapshot = _build_sync_backup_snapshot(effective_days)

    os.makedirs(SYNC_BACKUP_DIR, exist_ok=True)
    timestamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    path = os.path.join(SYNC_BACKUP_DIR, f"sync_backup_{timestamp}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False)

    _audit_sync_event("sync_backup_file", {"path": path, "count": snapshot.get("count", 0)})
    return path


def _start_sync_backup_scheduler():
    if SYNC_BACKUP_INTERVAL_MINUTES <= 0:
        return

    def worker():
        while True:
            try:
                _run_sync_backup_to_file()
            except Exception as exc:
                app.logger.warning("Scheduled sync backup failed: %s", exc)
            time.sleep(max(1, SYNC_BACKUP_INTERVAL_MINUTES) * 60)

    thread = threading.Thread(target=worker, daemon=True, name="sync-backup-scheduler")
    thread.start()


def _should_load_shed_for_endpoint() -> tuple[bool, int]:
    endpoint = request.path
    low_priority_prefixes = [
        "/sync/metrics",
        "/sync/alerts",
        "/sync/export",
        "/sync/backup",
    ]
    is_low_priority = any(endpoint.startswith(prefix) for prefix in low_priority_prefixes)
    if not is_low_priority:
        return False, 0

    window_requests = int(_sync_metrics.get("window_requests", 0))
    if window_requests >= SYNC_LOAD_SHED_REQUESTS_PER_MINUTE:
        return True, SYNC_LOAD_SHED_RETRY_AFTER_SECONDS
    return False, 0


@app.before_request
def _apply_load_shedding_guard():
    shed, retry_after = _should_load_shed_for_endpoint()
    if not shed:
        return None

    response = jsonify({
        "error": "Load shedding active",
        "retry_after": retry_after,
    })
    response.status_code = 503
    response.headers["Retry-After"] = str(retry_after)
    return response


def _maybe_inject_sync_chaos():
    if _is_sync_data_endpoint(request.path):
        g.sync_chaos_delay_applied_ms = 0
        g.sync_chaos_injected_failure = False

    if SYNC_CHAOS_DELAY_MS > 0:
        time.sleep(max(0, SYNC_CHAOS_DELAY_MS) / 1000.0)
        if _is_sync_data_endpoint(request.path):
            g.sync_chaos_delay_applied_ms = SYNC_CHAOS_DELAY_MS

    if SYNC_CHAOS_FAIL_RATE > 0 and random.random() < SYNC_CHAOS_FAIL_RATE:
        if _is_sync_data_endpoint(request.path):
            g.sync_chaos_injected_failure = True
        return jsonify({"error": "Chaos injected failure"}), 500

    return None


def _reject_if_writes_paused():
    if not _sync_writes_paused:
        return None

    response = jsonify({
        "error": "Writes temporarily paused for backup consistency",
        "retry_after": 2,
    })
    response.status_code = 503
    response.headers["Retry-After"] = "2"
    return response


def _encode_pull_cursor(server_created_at: str, local_id: str) -> str:
    raw = json.dumps(
        {
            "server_created_at": server_created_at,
            "local_id": local_id,
        },
        separators=(",", ":"),
    )
    return base64.urlsafe_b64encode(raw.encode("utf-8")).decode("ascii")


def _decode_pull_cursor(cursor_raw: str | None) -> tuple[str | None, str]:
    if not isinstance(cursor_raw, str) or not cursor_raw.strip():
        return None, ""

    try:
        raw = base64.urlsafe_b64decode(cursor_raw.encode("ascii")).decode("utf-8")
        parsed = json.loads(raw)
    except Exception:
        return None, ""

    created_at = parsed.get("server_created_at")
    local_id = parsed.get("local_id")
    if not isinstance(created_at, str) or not _is_valid_iso_datetime(created_at):
        return None, ""
    if not isinstance(local_id, str):
        local_id = ""
    return created_at, local_id


def _current_or_next_cursor(fallback_created_at: str, fallback_local_id: str, selected_rows: list[dict], next_cursor: str | None) -> str | None:
    if next_cursor:
        return next_cursor
    if selected_rows:
        last = selected_rows[-1]
        return _encode_pull_cursor(
            str(last.get("server_created_at", "")),
            str(last.get("local_id", "")),
        )
    if fallback_created_at:
        return _encode_pull_cursor(fallback_created_at, fallback_local_id)
    return None


@app.before_request
def _init_sync_request_timing():
    if _is_sync_data_endpoint(request.path):
        g.sync_request_started_at = time.perf_counter()
        g.sync_chaos_delay_applied_ms = 0
        g.sync_chaos_injected_failure = False


@app.after_request
def _record_sync_request_metrics(response):
    if not _is_sync_data_endpoint(request.path):
        return response

    started = getattr(g, "sync_request_started_at", None)
    if started is None:
        return response

    latency_ms = max(0.0, (time.perf_counter() - started) * 1000.0)
    endpoint = request.path

    endpoint_metrics = _sync_metrics.setdefault("endpoint_metrics", {})
    ep = endpoint_metrics.setdefault(endpoint, {
        "requests": 0,
        "status_2xx": 0,
        "status_4xx": 0,
        "status_5xx": 0,
        "latency_ms_total": 0.0,
        "latency_ms_max": 0.0,
    })
    ep["requests"] += 1
    status_code = int(getattr(response, "status_code", 0) or 0)
    if 200 <= status_code < 300:
        ep["status_2xx"] += 1
    elif 400 <= status_code < 500:
        ep["status_4xx"] += 1
    elif status_code >= 500:
        ep["status_5xx"] += 1
    ep["latency_ms_total"] += latency_ms
    ep["latency_ms_max"] = max(float(ep.get("latency_ms_max", 0.0)), latency_ms)

    chaos_corr = _sync_metrics.setdefault("chaos_correlation", {
        "chaos_requests": 0,
        "chaos_success": 0,
        "chaos_failure": 0,
        "chaos_latency_ms_total": 0.0,
        "chaos_delay_ms_total": 0,
        "chaos_injected_failures": 0,
        "non_chaos_requests": 0,
        "non_chaos_success": 0,
        "non_chaos_failure": 0,
        "non_chaos_latency_ms_total": 0.0,
    })

    chaos_delay_applied_ms = int(getattr(g, "sync_chaos_delay_applied_ms", 0) or 0)
    chaos_injected_failure = bool(getattr(g, "sync_chaos_injected_failure", False))
    chaos_applied = chaos_delay_applied_ms > 0 or chaos_injected_failure

    if chaos_applied:
        chaos_corr["chaos_requests"] += 1
        chaos_corr["chaos_latency_ms_total"] += latency_ms
        chaos_corr["chaos_delay_ms_total"] += max(0, chaos_delay_applied_ms)
        if status_code < 400:
            chaos_corr["chaos_success"] += 1
        else:
            chaos_corr["chaos_failure"] += 1
    else:
        chaos_corr["non_chaos_requests"] += 1
        chaos_corr["non_chaos_latency_ms_total"] += latency_ms
        if status_code < 400:
            chaos_corr["non_chaos_success"] += 1
        else:
            chaos_corr["non_chaos_failure"] += 1

    if chaos_injected_failure:
        chaos_corr["chaos_injected_failures"] += 1

    if endpoint in {"/save", "/save/batch", "/save/status", "/sync/pull"} and status_code == 429:
        _sync_metrics["backpressure_rejections"] = int(_sync_metrics.get("backpressure_rejections", 0)) + 1

    return response


def _send_webhook_alert(payload: dict):
    if not SYNC_ALERT_WEBHOOK_TARGETS:
        return

    body = json.dumps(payload).encode("utf-8")
    for url in SYNC_ALERT_WEBHOOK_TARGETS:
        delivered = False
        for attempt in range(max(1, SYNC_ALERT_DELIVERY_RETRIES)):
            try:
                req = urllib_request.Request(
                    url,
                    data=body,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with urllib_request.urlopen(req, timeout=3):
                    delivered = True
                    break
            except (urllib_error.URLError, TimeoutError, ValueError) as exc:
                app.logger.warning(
                    "Failed to deliver sync alert webhook url=%s attempt=%s error=%s",
                    url,
                    attempt + 1,
                    exc,
                )
                if attempt + 1 < max(1, SYNC_ALERT_DELIVERY_RETRIES):
                    time.sleep(min(2 ** attempt, 5))
        if delivered:
            # One successful channel is enough for delivery.
            return


def _send_sync_alerts_if_needed():
    alerts = _compute_sync_alerts()
    current_types = {str(alert.get("type", "unknown")) for alert in alerts}
    known_types = set(_sync_alert_active.keys()) | current_types

    now_ts = time.time()
    for alert_type in known_types:
        is_active_now = alert_type in current_types
        was_active = _sync_alert_active.get(alert_type, False)

        # Notify only on state transitions, plus cooldown guard.
        if is_active_now != was_active:
            last_sent_at = _sync_alert_state.get(alert_type, 0.0)
            if now_ts - last_sent_at < SYNC_ALERT_COOLDOWN_SECONDS:
                continue

            matching_alert = next((a for a in alerts if str(a.get("type", "unknown")) == alert_type), None)
            payload = {
                "service": "osteocare-sync",
                "timestamp": datetime.utcnow().isoformat(),
                "event": "alert_raised" if is_active_now else "alert_recovered",
                "alert_type": alert_type,
                "alert": matching_alert,
            }
            _send_webhook_alert(payload)
            _sync_alert_state[alert_type] = now_ts
            _sync_alert_active[alert_type] = is_active_now


def _verify_sync_signature(secret: str, raw_body: bytes):
    timestamp_raw = request.headers.get("X-Sync-Timestamp", "").strip()
    nonce = request.headers.get("X-Sync-Nonce", "").strip()
    signature = request.headers.get("X-Signature", "").strip().lower()
    signature_version = request.headers.get("X-Signature-Version", "1").strip()
    key_for_version = SYNC_SIGNING_KEYS.get(signature_version)
    if key_for_version is None:
        return jsonify({"error": "Unsupported signature version"}), 401
    if not timestamp_raw or not nonce or not signature:
        return jsonify({"error": "Missing signature headers"}), 401

    try:
        timestamp_val = int(timestamp_raw)
    except Exception:
        return jsonify({"error": "Invalid signature timestamp"}), 401

    now_ts = int(time.time())
    if abs(now_ts - timestamp_val) > SYNC_SIGNATURE_MAX_SKEW_SECONDS:
        return jsonify({"error": "Signature timestamp skew too large"}), 401

    _prune_old_nonces(float(now_ts))
    if nonce in _sync_nonce_cache:
        return jsonify({"error": "Replay detected"}), 409

    body_hash = hashlib.sha256(raw_body).digest()
    body_hash_b64 = base64.b64encode(body_hash).decode("ascii")
    message = f"{timestamp_raw}.{nonce}.{body_hash_b64}".encode("utf-8")
    effective_secret = key_for_version if secret == SYNC_SIGNING_SECRET else f"{secret}:{key_for_version}"
    expected = hmac.new(effective_secret.encode("utf-8"), message, hashlib.sha256).hexdigest().lower()
    if not hmac.compare_digest(expected, signature):
        return jsonify({"error": "Invalid signature"}), 401

    _sync_nonce_cache[nonce] = float(now_ts)
    _sync_nonce_cache.move_to_end(nonce)
    while len(_sync_nonce_cache) > max(1000, SYNC_NONCE_CACHE_MAX_SIZE):
        _sync_nonce_cache.popitem(last=False)
    return None


def _require_sync_security(raw_body: bytes):
    user_id, user_err = _require_user_id()
    if user_err:
        return None, user_err

    auth_header = request.headers.get("Authorization", "").strip()
    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):].strip()
        try:
            payload = decode_token(token)
        except Exception:
            return None, (jsonify({"error": "Invalid authorization token"}), 401)

        token_user_id = str(payload.get("user_id", "")).strip()
        if token_user_id != user_id:
            return None, (jsonify({"error": "Token user mismatch"}), 403)

        sig_err = _verify_sync_signature(token, raw_body)
        if sig_err:
            return None, sig_err
        return user_id, None

    key_err = _require_api_key()
    if key_err:
        return None, key_err

    sig_err = _verify_sync_signature(SYNC_SIGNING_SECRET, raw_body)
    if sig_err:
        return None, sig_err
    return user_id, None


def _compute_sync_alerts() -> list[dict]:
    total = _sync_metrics["records_received"]
    failed = _sync_metrics["records_failed"]
    alerts: list[dict] = []

    if total > 0:
        failure_rate = failed / total
        if failure_rate >= SYNC_ALERT_FAILURE_RATE:
            alerts.append({
                "type": "failure_rate",
                "severity": "warning",
                "message": f"Sync failure rate high: {failure_rate:.2%}",
                "value": round(failure_rate, 4),
                "threshold": SYNC_ALERT_FAILURE_RATE,
            })

    if failed >= SYNC_ALERT_FAILURE_COUNT:
        alerts.append({
            "type": "failure_count",
            "severity": "warning",
            "message": f"Sync failure count high: {failed}",
            "value": failed,
            "threshold": SYNC_ALERT_FAILURE_COUNT,
        })

    cursor_submissions = int(_sync_metrics.get("cursor_submissions", 0) or 0)
    cursor_regressions = int(_sync_metrics.get("cursor_regressions", 0) or 0)
    if cursor_submissions >= max(1, SYNC_CURSOR_ALERT_MIN_SUBMISSIONS):
        regression_rate = cursor_regressions / max(1, cursor_submissions)
        if regression_rate >= SYNC_CURSOR_ALERT_REGRESSION_RATE:
            alerts.append({
                "type": "cursor_regression_rate",
                "severity": "warning",
                "message": f"Cursor regression rate high: {regression_rate:.2%}",
                "value": round(regression_rate, 4),
                "threshold": SYNC_CURSOR_ALERT_REGRESSION_RATE,
            })

    return alerts


def _parse_json_payload() -> dict | None:
    try:
        raw = request.get_data(cache=True)
        if not raw:
            return request.get_json(silent=True)

        if request.headers.get("Content-Encoding", "").lower() == "gzip":
            raw = gzip.decompress(raw)

        decoded = json.loads(raw.decode("utf-8"))
        if isinstance(decoded, dict):
            return decoded
        return None
    except Exception:
        return request.get_json(silent=True)


# ------------------------------------------
# Form → model feature mapping helpers
# ------------------------------------------
FRIENDLY_BOOL_MAP = {
    "MCQ366A": "memory_issue",
    "MCQ371A": "mobility_climb",
    "MCQ371D": "stand_long",
    "MCQ092": "activity_limited",
    "MCQ160G": "arthritis",
    "MCQ160L": "thyroid",
    "MCQ160K": "lung_disease",
    "MCQ160B": "heart_failure",
    "MCQ230A": "smoking",
}

FRIENDLY_ALCOHOL_KEY = "alcohol"  # maps to MCQ550
FRIENDLY_HEALTH_KEY = "general_health"  # maps to MCQ025
FRIENDLY_CALCIUM_KEY = "calcium_frequency"  # maps to calcium_level

# Survey questions mapping for the guided form
SURVEY_QUESTIONS = [
    # Demographics
    {
        "id": 1,
        "field_name": "age",
        "question": "What is your age?",
        "type": "number_input",
        "options": [],
        "help_text": "Enter your age in years (must be 18 or older)",
        "required": True,
    },
    {
        "id": 2,
        "field_name": "gender",
        "question": "What is your gender?",
        "type": "select",
        "options": [
            {"value": "Male", "label": "Male"},
            {"value": "Female", "label": "Female"},
        ],
        "help_text": "Select your gender",
        "required": True,
    },
    {
        "id": 3,
        "field_name": "height_weight",
        "question": "What is your height and weight?",
        "type": "height_weight",
        "options": [],
        "help_text": "Enter your height in feet and inches and weight in kilograms.",
        "sub_fields": [
            {"field_name": "height_feet", "label": "Height (Feet)", "type": "dropdown", "required": True, "options": [4, 5, 6, 7]},
            {"field_name": "height_inches", "label": "Height (Inches)", "type": "dropdown", "required": True, "options": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]},
            {"field_name": "weight_kg", "label": "Weight (kg)", "type": "number_input", "required": True},
        ],
        "required": True,
    },
    {
        "id": 4,
        "field_name": "calcium_frequency",
        "question": "How often do you consume milk, curd, paneer, or calcium-rich foods?",
        "type": "select",
        "options": [
            {"value": "Rarely", "label": "Rarely"},
            {"value": "Sometimes", "label": "Sometimes"},
            {"value": "Daily", "label": "Daily"},
        ],
        "help_text": "Calcium intake is crucial for bone health",
        "required": False,
    },
    # Functional / Frailty Indicators
    {
        "id": 5,
        "field_name": "memory_issue",
        "question": "Do you have serious difficulty remembering or concentrating?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Cognitive function is linked to overall health",
        "required": False,
    },
    {
        "id": 6,
        "field_name": "mobility_climb",
        "question": "Do you have difficulty walking or climbing stairs?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Mobility issues may indicate muscle and bone weakness",
        "required": False,
    },
    {
        "id": 7,
        "field_name": "stand_long",
        "question": "Do you have difficulty standing for long periods?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Standing endurance relates to bone and muscle strength",
        "required": False,
    },
    {
        "id": 8,
        "field_name": "activity_limited",
        "question": "Are you limited in daily physical activities due to health problems?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Physical activity limitations can affect bone density",
        "required": False,
    },
    # Medical Conditions
    {
        "id": 9,
        "field_name": "arthritis",
        "question": "Has a doctor ever told you that you have arthritis (joint disease)?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Arthritis is a long-term joint condition that causes pain, stiffness, or swelling, especially in knees, hips, hands, or spine.",
        "note_text": "This refers only to a diagnosis given by a doctor.",
        "info_text": "What is arthritis?\\n\\n• A condition affecting joints\\n• Causes long-term pain or stiffness\\n• Common in older adults\\n• Includes osteoarthritis and rheumatoid arthritis\\n• This question refers to a confirmed medical diagnosis",
        "required": False,
    },
    {
        "id": 10,
        "field_name": "thyroid",
        "question": "Have you been diagnosed with thyroid disease?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Thyroid function affects bone metabolism",
        "required": False,
    },
    {
        "id": 11,
        "field_name": "lung_disease",
        "question": "Have you been diagnosed with chronic lung disease?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Lung disease can be associated with bone health issues",
        "required": False,
    },
    {
        "id": 12,
        "field_name": "heart_failure",
        "question": "Have you been diagnosed with congestive heart failure?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Heart conditions may affect overall bone health",
        "required": False,
    },
    # Lifestyle Factors
    {
        "id": 13,
        "field_name": "smoking",
        "question": "Have you smoked regularly?",
        "type": "yes_no",
        "options": [
            {"value": "Yes", "label": "Yes"},
            {"value": "No", "label": "No"},
        ],
        "help_text": "Smoking accelerates bone loss",
        "required": False,
    },
    {
        "id": 14,
        "field_name": "alcohol",
        "question": "How often do you drink alcohol?",
        "type": "select",
        "options": [
            {"value": "None", "label": "None"},
            {"value": "Occasionally", "label": "Occasionally"},
            {"value": "Frequently", "label": "Frequently"},
        ],
        "help_text": "Excess alcohol consumption affects bone strength",
        "required": False,
    },
    {
        "id": 15,
        "field_name": "general_health",
        "question": "How would you rate your overall health?",
        "type": "select",
        "options": [
            {"value": "Excellent", "label": "Excellent"},
            {"value": "Good", "label": "Good"},
            {"value": "Fair", "label": "Fair"},
            {"value": "Poor", "label": "Poor"},
        ],
        "help_text": "Your overall health status influences bone health",
        "required": False,
    },
]


def _encode_yes_no(value):
    if isinstance(value, (bool, int)):
        return int(bool(value))
    if value is None:
        return 0
    text = str(value).strip().lower()
    if text in {"yes", "y", "true", "1"}:
        return 1
    if text in {"no", "n", "false", "0"}:
        return 0
    return 0


def _encode_gender(value):
    if isinstance(value, (int, float)):
        return int(value)
    text = str(value).strip().lower()
    if text in {"male", "m"}:
        return 1
    if text in {"female", "f"}:
        return 2
    return 0


def _encode_alcohol(value):
    if value is None:
        return 0
    text = str(value).strip().lower()
    if text in {"none", "no", "never"}:
        return 0
    return 1  # occasionally / frequently


def _encode_health(value):
    if value is None:
        return 0
    text = str(value).strip().lower()
    if text in {"excellent", "good"}:
        return 0
    if text in {"fair", "poor"}:
        return 1
    return 0


def _encode_calcium_frequency(value):
    if value is None:
        return 1  # default mid bucket
    text = str(value).strip().lower()
    if text in {"rarely", "low", "0"}:
        return 0
    if text in {"daily", "high", "2"}:
        return 2
    return 1  # sometimes / default


def _compute_bmi(form_entry: dict) -> float | None:
    h = form_entry.get("height_cm")
    w = form_entry.get("weight_kg")
    try:
        if h is None or w is None:
            return None
        h_m = float(h) / 100.0
        w_kg = float(w)
        if h_m <= 0:
            return None
        return w_kg / (h_m * h_m)
    except Exception:  # pragma: no cover - defensive
        return None


def _risk_level(prob: float) -> str:
    """
    Risk categories MUST match training pipeline.
    Training thresholds:
        <0.10  -> Low
        <0.20  -> Moderate
        >=0.20 -> High
    """
    if prob < 0.10:
        return "Low"
    elif prob < 0.20:
        return "Moderate"
    else:
        return "High"


def _risk_message(level: str) -> str:
    if level == "Low":
        return "Your bone health appears stable. Maintain healthy habits and reassess periodically."
    if level == "Moderate":
        return "Early risk indicators detected. Lifestyle improvements are recommended."
    return "Strong osteoporosis risk patterns observed. Preventive action and clinical screening advised."


def _get_reassessment_days(risk_level: str) -> int:
    if risk_level == "Low":
        return 180
    if risk_level == "Moderate":
        return 90
    if risk_level == "High":
        return 30
    return 90


def _compute_next_reassessment_date(risk_level: str) -> str:
    days = _get_reassessment_days(risk_level)
    next_date = datetime.now() + timedelta(days=days)
    return next_date.strftime("%Y-%m-%d")


def _is_yes_answer(value) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"yes", "true", "1"}


def _user_language_code(user_id: str) -> str:
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute("SELECT preferred_language FROM users WHERE id = ?", (user_id,))
        row = cur.fetchone()
    finally:
        conn.close()

    pref = str(row[0]).strip().lower() if row and row[0] is not None else "english"
    if pref == "hindi":
        return "hi"
    if pref == "telugu":
        return "te"
    return "en"


def _derive_reminder_tags(form_entry: dict, risk_level: str) -> list[str]:
    tags: list[str] = []

    calcium_frequency = str(form_entry.get("calcium_frequency", "")).strip().lower()
    if calcium_frequency in {"rarely", "sometimes", "none"}:
        tags.extend(["calcium_low", "diet_poor", "calcium_sources", "vitamin_d_low"])

    if _is_yes_answer(form_entry.get("smoking")):
        tags.append("smoking")

    alcohol = str(form_entry.get("alcohol", "")).strip().lower()
    if alcohol in {"occasionally", "frequently", "daily", "weekly"}:
        tags.append("alcohol")

    if _is_yes_answer(form_entry.get("activity_limited")):
        tags.extend(["exercise_low", "mobility_low", "walking", "strength_training"])
    if _is_yes_answer(form_entry.get("mobility_climb")):
        tags.extend(["mobility_low", "balance_low", "stairs_caution", "assist_device"])
    if _is_yes_answer(form_entry.get("stand_long")):
        tags.extend(["posture_bad", "sitting_long", "breaks", "stretching"])
    if _is_yes_answer(form_entry.get("memory_issue")):
        tags.extend(["symptom_tracking", "weakness", "social_activity"])

    if _is_yes_answer(form_entry.get("arthritis")):
        tags.extend(["pain_monitoring", "physiotherapy", "joint_stiffness", "pain_increase"])
    if _is_yes_answer(form_entry.get("thyroid")):
        tags.extend(["doctor_visit", "followup"])
    if _is_yes_answer(form_entry.get("lung_disease")):
        tags.extend(["doctor_visit", "followup"])
    if _is_yes_answer(form_entry.get("heart_failure")):
        tags.extend(["doctor_visit", "followup"])

    general_health = str(form_entry.get("general_health", "")).strip().lower()
    if general_health in {"poor", "fair"}:
        tags.extend(["symptom_tracking", "pain_monitoring", "fatigue", "weakness"])

    age_val = int(float(form_entry.get("age", 0) or 0))
    if age_val >= 51:
        tags.extend(["fall_risk", "footwear", "lighting", "home_safety", "slippery_floor", "stairs_caution", "social_activity"])

    bmi = _compute_bmi(form_entry)
    if bmi is not None:
        if bmi < 18.5:
            tags.extend(["protein_low", "protein_sources"])
        if bmi >= 27:
            tags.append("weight_monitoring")

    # Core reminders to keep coverage broad without showing everything.
    tags.extend([
        "sunlight_low",
        "sunlight_consistency",
        "hydration_low",
        "hydration_reminder",
        "sleep_schedule",
        "routine",
        "activity",
        "early_sleep",
    ])

    risk_lower = risk_level.strip().lower()
    if risk_lower == "high":
        tags.extend([
            "doctor_visit",
            "medication",
            "supplements",
            "supervised_exercise",
            "heavy_lifting",
            "sudden_movement",
            "assist_device",
            "emergency_contact",
            "followup",
            "pain_increase",
            "caregiver_support",
        ])
    elif risk_lower == "moderate":
        tags.extend(["doctor_visit", "fall_risk", "exercise_low", "bone_density_test", "slippery_floor"])
    else:
        tags.extend(["exercise_low", "walking", "strength_training"])

    # Preserve order while removing duplicates.
    seen: set[str] = set()
    deduped: list[str] = []
    for tag in tags:
        clean = str(tag).strip().lower()
        if not clean or clean in seen:
            continue
        seen.add(clean)
        deduped.append(clean)
    return deduped


PRIORITY_SCORE = {
    "high": 3,
    "medium": 2,
    "low": 1,
}

TIME_WEIGHT = {
    "exact": 1.5,
    "neutral": 1.0,
    "mismatch": 0.8,
}

CORE_FALLBACK = [
    "exercise_low",
    "sleep_poor",
    "hydration_low",
]

SHAP_TAG_MAPPING = {
    "smoking": ["smoking"],
    "calcium_intake": ["calcium_low", "calcium_sources"],
    "calcium_frequency": ["calcium_low", "calcium_sources"],
    "exercise": ["exercise_low", "walking", "strength_training"],
    "activity": ["activity", "exercise_low"],
    "mobility": ["mobility_low", "balance_low"],
    "sunlight": ["sunlight_low", "sunlight_consistency", "vitamin_d_low"],
    "sleep": ["sleep_poor", "sleep_schedule", "early_sleep"],
    "hydration": ["hydration_low", "hydration_reminder"],
    "alcohol": ["alcohol"],
    "pain": ["pain_monitoring", "pain_increase"],
    "fall_risk": ["fall_risk", "slippery_floor", "home_safety"],
}


def _get_current_time_slot() -> str:
    hour = datetime.now().hour
    if 5 <= hour < 12:
        return "morning"
    if 12 <= hour < 17:
        return "afternoon"
    return "evening"


def _normalize_shap_values(raw_shap_values) -> dict[str, float]:
    if not isinstance(raw_shap_values, dict):
        return {}

    normalized: dict[str, float] = {}
    for key, value in raw_shap_values.items():
        feature = str(key).strip().lower()
        if not feature:
            continue
        try:
            score = float(value)
        except Exception:
            continue
        normalized[feature] = score
    return normalized


def _map_shap_to_tag_scores(shap_values: dict[str, float]) -> dict[str, float]:
    tag_scores: dict[str, float] = {}
    for feature, raw_score in shap_values.items():
        # Positive SHAP values increase risk and should drive preventive reminders.
        if raw_score <= 0:
            continue

        mapped_tags = SHAP_TAG_MAPPING.get(feature, [])
        if not mapped_tags and feature in {"thyroid", "lung_disease", "heart_failure"}:
            mapped_tags = ["doctor_visit", "followup"]

        for tag in mapped_tags:
            previous = float(tag_scores.get(tag, 0.0))
            if raw_score > previous:
                tag_scores[tag] = raw_score
    return tag_scores


def _normalize_tag_scores(tag_scores: dict[str, float]) -> dict[str, float]:
    total = sum(abs(float(v)) for v in tag_scores.values()) or 1.0
    return {
        str(tag).strip().lower(): float(value) / total
        for tag, value in tag_scores.items()
        if str(tag).strip()
    }


def _derive_shap_values_from_form(form_entry: dict) -> dict[str, float]:
    estimated: dict[str, float] = {}

    if _is_yes_answer(form_entry.get("smoking")):
        estimated["smoking"] = 0.85

    calcium_frequency = str(form_entry.get("calcium_frequency", "")).strip().lower()
    if calcium_frequency == "rarely":
        estimated["calcium_intake"] = 0.60
    elif calcium_frequency == "sometimes":
        estimated["calcium_intake"] = 0.35

    if _is_yes_answer(form_entry.get("activity_limited")) or _is_yes_answer(form_entry.get("mobility_climb")):
        estimated["exercise"] = 0.45
        estimated["mobility"] = 0.30

    if _is_yes_answer(form_entry.get("arthritis")):
        estimated["pain"] = 0.35

    alcohol = str(form_entry.get("alcohol", "")).strip().lower()
    if alcohol in {"occasionally", "frequently", "daily", "weekly"}:
        estimated["alcohol"] = 0.25

    age_val = int(float(form_entry.get("age", 0) or 0))
    if age_val >= 60:
        estimated["fall_risk"] = 0.30

    return estimated


def _fetch_reminder_rows(tags: list[str], risk_level: str, lang_code: str) -> list[dict]:
    if not tags:
        return []

    risk_lower = risk_level.strip().lower()
    text_col = "en"
    if lang_code == "te":
        text_col = "te"
    elif lang_code == "hi":
        text_col = "hi"

    placeholders = ",".join(["?"] * len(tags))
    query = f"""
        SELECT tag, priority, time_slot, {text_col} AS reminder_text
        FROM reminders
        WHERE tag IN ({placeholders})
          AND (lower(risk_level) = 'all' OR lower(risk_level) = ?)
    """

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute(query, [*tags, risk_lower])
        rows = cur.fetchall()
    finally:
        conn.close()

    reminders: list[dict] = []
    for row in rows:
        text = str(row["reminder_text"] or "").strip()
        if not text:
            continue
        reminders.append({
            "tag": str(row["tag"] or "").strip().lower(),
            "priority": str(row["priority"] or "low").strip().lower(),
            "time_slot": str(row["time_slot"] or "any").strip().lower(),
            "text": text,
            "category": _reminder_category(str(row["tag"] or "")),
        })
    return reminders


def _reminder_category(tag: str) -> str:
    value = str(tag).strip().lower()
    if value.startswith(("calcium", "vitamin", "protein", "diet", "fruit", "hydration", "salt", "junk", "caffeine")):
        return "nutrition"
    if value.startswith(("exercise", "walking", "strength", "stretch", "mobility", "balance", "physio", "posture", "sitting")):
        return "movement"
    if value.startswith(("sleep", "early_sleep", "screen_time")):
        return "sleep"
    if value.startswith(("doctor", "medication", "followup", "bone_density", "emergency", "supplements")):
        return "medical"
    if value.startswith(("fall", "slippery", "stairs", "footwear", "grab", "lighting", "home_safety", "assist")):
        return "safety"
    if value.startswith(("symptom", "pain", "weakness", "fatigue", "social", "caregiver")):
        return "monitoring"
    return "general"


def _apply_time_bonus(reminders: list[dict], current_slot: str) -> None:
    for reminder in reminders:
        reminder_slot = str(reminder.get("time_slot", "any")).strip().lower()
        if reminder_slot == current_slot:
            reminder["time_bonus"] = TIME_WEIGHT["exact"]
        elif reminder_slot == "any":
            reminder["time_bonus"] = TIME_WEIGHT["neutral"]
        else:
            reminder["time_bonus"] = TIME_WEIGHT["mismatch"]


def _compute_reminder_score(reminder: dict, tag_scores: dict[str, float]) -> float:
    shap_score = float(tag_scores.get(str(reminder.get("tag", "")).strip().lower(), 0.0))
    db_score = float(PRIORITY_SCORE.get(str(reminder.get("priority", "low")).strip().lower(), 1.0))
    time_bonus = float(reminder.get("time_bonus", 1.0) or 1.0)
    return (shap_score * 2.0 + db_score) * time_bonus


def _apply_smart_fallback(reminders: list[dict], existing_tags: set[str], risk_level: str, lang_code: str) -> list[dict]:
    needed = 3 - len(reminders)
    if needed <= 0:
        return reminders

    fallback_rows = _fetch_reminder_rows(CORE_FALLBACK, risk_level, lang_code)
    for row in fallback_rows:
        tag = str(row.get("tag", "")).strip().lower()
        if not tag or tag in existing_tags:
            continue
        reminders.append(row)
        existing_tags.add(tag)
        needed -= 1
        if needed <= 0:
            break
    return reminders


def _extract_top_factors(tag_scores: dict[str, float], limit: int = 2) -> list[str]:
    ranked = sorted(
        ((str(tag).strip().lower(), float(score)) for tag, score in tag_scores.items()),
        key=lambda item: item[1],
        reverse=True,
    )
    return [tag for tag, score in ranked[: max(0, limit)] if score > 0]


def _group_tasks_by_time(reminder_rows: list[dict]) -> dict[str, list[str]]:
    slot_order = ["morning", "afternoon", "evening", "night", "weekly", "any"]
    grouped: dict[str, list[str]] = {}
    for slot in slot_order:
        values = [
            str(item.get("text", "")).strip()
            for item in reminder_rows
            if str(item.get("time_slot", "")).strip().lower() == slot
            and str(item.get("text", "")).strip()
        ]
        if values:
            grouped[slot] = values
    return grouped


def _action_type_for_category(category: str) -> str:
    value = str(category).strip().lower()
    if value == "medical":
        return "medical"
    if value == "safety":
        return "safety"
    return "habit"


def _group_tasks_by_type(reminder_rows: list[dict]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {
        "habit": [],
        "medical": [],
        "safety": [],
    }
    for item in reminder_rows:
        text = str(item.get("text", "")).strip()
        if not text:
            continue
        action_type = _action_type_for_category(item.get("category", "general"))
        grouped[action_type].append(text)

    return {key: value for key, value in grouped.items() if value}


def _urgency_from_risk(risk_level: str) -> str:
    value = str(risk_level).strip().lower()
    if value == "high":
        return "high"
    if value == "moderate":
        return "medium"
    return "low"


def _get_max_shap(shap_values: dict[str, float] | None) -> float:
    if not isinstance(shap_values, dict) or not shap_values:
        return 0.0
    values = [abs(float(v)) for v in shap_values.values()]
    return max(values) if values else 0.0


def _compute_confidence(probability: float | None, shap_values: dict[str, float] | None) -> float:
    max_shap = _get_max_shap(shap_values)
    has_prob = isinstance(probability, (int, float))
    has_shap = bool(shap_values)

    if not has_prob and not has_shap:
        return 0.0
    if has_prob and not has_shap:
        return round(max(0.0, min(1.0, float(probability))), 2)
    if has_shap and not has_prob:
        return round(max(0.0, min(1.0, max_shap)), 2)

    confidence = 0.7 * float(probability) + 0.3 * max_shap
    return round(max(0.0, min(1.0, confidence)), 2)


def _get_confidence_label(confidence: float) -> str:
    if confidence >= 0.8:
        return "High"
    if confidence >= 0.6:
        return "Moderate"
    return "Low"


def _humanize_factor_tag(tag: str) -> str:
    factor = str(tag).strip().lower()
    aliases = {
        "calcium_low": "low calcium intake",
        "exercise_low": "low physical activity",
        "smoking": "smoking habit",
        "sunlight_low": "lack of sunlight",
        "sleep_poor": "poor sleep quality",
    }
    if factor in aliases:
        return aliases[factor]
    return factor.replace("_", " ")


def _build_confidence_reason(top_factors: list[str]) -> str:
    if len(top_factors) >= 2:
        return (
            f"Main factors: {_humanize_factor_tag(top_factors[0])} "
            f"and {_humanize_factor_tag(top_factors[1])}."
        )
    if top_factors:
        return f"Main factor: {_humanize_factor_tag(top_factors[0])}."
    return "Multiple factors influence your result."


def _top_factors_with_weight(raw_tag_scores: dict[str, float], limit: int = 3) -> list[dict]:
    ranked = sorted(
        ((str(tag).strip().lower(), abs(float(score))) for tag, score in raw_tag_scores.items()),
        key=lambda item: item[1],
        reverse=True,
    )
    factors = [
        {"factor": tag, "impact": round(score, 2)}
        for tag, score in ranked[: max(0, limit)]
        if score > 0
    ]

    max_impact = max((float(item.get("impact", 0.0)) for item in factors), default=0.0) or 1.0
    for item in factors:
        item["normalized"] = round(float(item.get("impact", 0.0)) / max_impact, 2)

    return factors


def _fallback_task_for_factor(factor: str, risk_level: str = "") -> str:
    factor_key = str(factor).strip().lower()
    risk = str(risk_level).strip().lower()

    if factor_key == "smoking":
        if risk == "high":
            return "Stop smoking immediately to reduce your bone risk"
        return "Reducing smoking can improve your bone health"

    if factor_key == "calcium_low":
        return "Increase calcium intake through diet or supplements"

    fallback_map = {
        "smoking": "Stop smoking immediately",
        "calcium_low": "Start your day with a calcium-rich breakfast",
        "exercise_low": "Do at least 30 minutes of exercise",
        "sunlight_low": "Get 20 minutes of sunlight daily",
        "sleep_poor": "Ensure 7-8 hours of sleep",
    }
    return fallback_map.get(factor_key, "Follow the recommended daily plan")


def _contextualize_factor_task(factor: str, task_text: str, risk_level: str) -> str:
    factor_key = str(factor).strip().lower()
    text = str(task_text).strip()
    risk = str(risk_level).strip().lower()
    if not text:
        return _fallback_task_for_factor(factor_key, risk_level=risk)

    if factor_key == "smoking":
        if risk == "high":
            return "Stop smoking immediately to reduce your bone risk"
        return "Reducing smoking can improve your bone health"

    if factor_key == "calcium_low":
        return "Increase calcium intake through diet or supplements"

    return text


def _factor_task_link(top_factors: list[str], reminder_rows: list[dict], risk_level: str) -> dict[str, str]:
    link: dict[str, str] = {}
    tag_to_task = {
        str(item.get("tag", "")).strip().lower(): str(item.get("text", "")).strip()
        for item in reminder_rows
        if str(item.get("tag", "")).strip() and str(item.get("text", "")).strip()
    }

    for factor in top_factors:
        factor_key = str(factor).strip().lower()
        link[factor_key] = _contextualize_factor_task(
            factor_key,
            tag_to_task.get(factor_key, ""),
            risk_level,
        )
    return link


def _get_confidence_note(risk_level: str, confidence: float) -> str:
    risk = str(risk_level).strip().lower()
    if risk == "high" and confidence < 0.6:
        return "Risk detected but with moderate certainty"
    if risk == "high" and confidence >= 0.6:
        return "Risk detected with high certainty"
    if risk == "low" and confidence > 0.7:
        return "Low risk confirmed with high confidence"
    if risk == "moderate" and confidence < 0.6:
        return "Moderate risk detected with limited certainty"
    return "Current inputs provide limited predictive certainty."


def _get_confidence_band(confidence: float) -> str:
    if confidence >= 0.85:
        return "Very High"
    if confidence >= 0.7:
        return "High"
    if confidence >= 0.55:
        return "Moderate"
    return "Low"


def _generate_tasks_bundle(
    form_entry: dict,
    user_id: str,
    risk_level: str,
    shap_values: dict | None = None,
    current_slot: str | None = None,
    probability: float | None = None,
) -> dict:
    tags = _derive_reminder_tags(form_entry, risk_level)
    lang_code = _user_language_code(user_id)
    effective_slot = (current_slot or _get_current_time_slot()).strip().lower()

    normalized_shap = _normalize_shap_values(shap_values)
    if not normalized_shap:
        normalized_shap = _derive_shap_values_from_form(form_entry)

    raw_tag_scores = _map_shap_to_tag_scores(normalized_shap)
    tag_scores = _normalize_tag_scores(raw_tag_scores)
    top_factors = _extract_top_factors(tag_scores)
    top_factors_with_weight = _top_factors_with_weight(raw_tag_scores)
    provided_shap = _normalize_shap_values(shap_values) if isinstance(shap_values, dict) else {}
    confidence = _compute_confidence(probability, provided_shap)
    confidence_label = _get_confidence_label(confidence)
    confidence_band = _get_confidence_band(confidence)
    confidence_reason = _build_confidence_reason(top_factors)
    confidence_note = _get_confidence_note(risk_level, confidence)

    reminder_rows = _fetch_reminder_rows(tags, risk_level, lang_code)
    _apply_time_bonus(reminder_rows, effective_slot)

    for reminder in reminder_rows:
        reminder["score"] = _compute_reminder_score(reminder, tag_scores)

    reminder_rows.sort(
        key=lambda reminder: (
            float(reminder.get("score", 0.0)),
            float(PRIORITY_SCORE.get(str(reminder.get("priority", "low")).strip().lower(), 1.0)),
        ),
        reverse=True,
    )

    picked_rows: list[dict] = []
    seen_text: set[str] = set()
    seen_tags: set[str] = set()
    category_counts: dict[str, int] = {}
    max_per_category = 2

    for reminder in reminder_rows:
        text = str(reminder.get("text", "")).strip()
        tag = str(reminder.get("tag", "")).strip().lower()
        category = str(reminder.get("category", "general")).strip().lower()
        if not text or not tag:
            continue
        if text.lower() in seen_text or tag in seen_tags:
            continue
        if category_counts.get(category, 0) >= max_per_category:
            continue

        seen_text.add(text.lower())
        seen_tags.add(tag)
        category_counts[category] = category_counts.get(category, 0) + 1
        picked_rows.append(reminder)
        if len(picked_rows) >= 5:
            break

    # If diversity cap was too strict, fill remaining with next best unique reminders.
    if len(picked_rows) < 5:
        for reminder in reminder_rows:
            text = str(reminder.get("text", "")).strip()
            tag = str(reminder.get("tag", "")).strip().lower()
            if not text or not tag:
                continue
            if text.lower() in seen_text or tag in seen_tags:
                continue
            seen_text.add(text.lower())
            seen_tags.add(tag)
            picked_rows.append(reminder)
            if len(picked_rows) >= 5:
                break

    picked_rows = _apply_smart_fallback(picked_rows, seen_tags, risk_level, lang_code)

    final_rows = picked_rows[:5]
    tasks = [str(row.get("text", "")).strip() for row in final_rows if str(row.get("text", "")).strip()]
    time_groups = _group_tasks_by_time(final_rows)
    type_groups = _group_tasks_by_type(final_rows)
    factor_task_link = _factor_task_link(top_factors, final_rows, risk_level)
    primary_action = ""
    if top_factors:
        primary_action = factor_task_link.get(str(top_factors[0]).strip().lower(), "")
    if not primary_action and tasks:
        primary_action = tasks[0]

    return {
        "tasks": tasks,
        "matched_tags": tags,
        "top_factors": top_factors,
        "top_factors_with_weight": top_factors_with_weight,
        "factor_task_link": factor_task_link,
        "primary_action": primary_action,
        "slot_used": effective_slot,
        "time_groups": time_groups,
        "type_groups": type_groups,
        "confidence": confidence,
        "confidence_label": confidence_label,
        "confidence_band": confidence_band,
        "confidence_reason": confidence_reason,
        "confidence_note": confidence_note,
    }


def _generate_tasks(
    form_entry: dict,
    user_id: str,
    risk_level: str,
    shap_values: dict | None = None,
    current_slot: str | None = None,
) -> tuple[list[str], list[str]]:
    bundle = _generate_tasks_bundle(
        form_entry,
        user_id=user_id,
        risk_level=risk_level,
        shap_values=shap_values,
        current_slot=current_slot,
    )
    return list(bundle.get("tasks", [])), list(bundle.get("matched_tags", []))


def _medical_alerts(form_entry: dict) -> list[str]:
    alerts: list[str] = []
    conditions = [
        form_entry.get("arthritis"),
        form_entry.get("thyroid"),
        form_entry.get("lung_disease"),
        form_entry.get("heart_failure"),
    ]
    # Handle both boolean (true/false) and string ("Yes"/"No") values
    def is_positive(val):
        if isinstance(val, bool):
            return val
        return str(val).lower() == "yes"
    
    if any(is_positive(c) for c in conditions):
        alerts.append("Existing medical condition may increase bone risk. Clinical screening recommended.")

    # General health signal
    if str(form_entry.get("general_health", "")).lower() in {"fair", "poor"}:
        alerts.append("Overall health concerns noted. Consider discussing bone health with your clinician.")

    return alerts


def _map_form_entry(form_entry: dict, feature_order: list[str]) -> dict:
    """Map a guided-form entry into the exact model feature vector."""
    row = {feat: 0 for feat in feature_order}

    # Age and age^2
    age = form_entry.get("age")
    if age is None:
        raise ValueError("'age' is required")
    age_val = float(age)
    if "RIDAGEYR" in row:
        row["RIDAGEYR"] = age_val
    if "AGE_SQUARED" in row:
        row["AGE_SQUARED"] = age_val * age_val

    # Gender
    if "RIAGENDR" in row:
        row["RIAGENDR"] = _encode_gender(form_entry.get("gender"))

    # BMI from height/weight if present
    if "BMXBMI" in row:
        feet = form_entry.get("height_feet")
        inches = form_entry.get("height_inches")
        w = form_entry.get("weight_kg")
        if feet is None or inches is None or w is None:
            raise ValueError("'height_feet', 'height_inches', and 'weight_kg' are required to compute BMI")
        try:
            feet_val = float(feet)
            inches_val = float(inches)
            w_kg = float(w)
            # height_cm = (feet * 30.48) + (inches * 2.54)
            height_cm = (feet_val * 30.48) + (inches_val * 2.54)
            h_m = height_cm / 100.0
            bmi = w_kg / (h_m * h_m) if h_m > 0 else 0
        except Exception as exc:  # pragma: no cover - bad numeric input
            raise ValueError(f"Invalid height/weight: {exc}")
        row["BMXBMI"] = bmi

    # Binary MCQ signals
    for col, friendly_key in FRIENDLY_BOOL_MAP.items():
        if col in row:
            row[col] = _encode_yes_no(form_entry.get(friendly_key))

    # Alcohol (MCQ550)
    if "MCQ550" in row:
        row["MCQ550"] = _encode_alcohol(form_entry.get(FRIENDLY_ALCOHOL_KEY))

    # General health (MCQ025)
    if "MCQ025" in row:
        row["MCQ025"] = _encode_health(form_entry.get(FRIENDLY_HEALTH_KEY))

    # Calcium intake proxy (mapped to model's binned calcium_level)
    if "calcium_level" in row:
        row["calcium_level"] = _encode_calcium_frequency(form_entry.get(FRIENDLY_CALCIUM_KEY))

    return row


# ------------------------------------------
# Authentication Routes
# ------------------------------------------

@app.route("/api/auth/signup", methods=["POST"])
@limiter.limit("5 per minute")  # Limit signup attempts
def api_signup():
    """
    Register a new user.
    
    Request JSON:
    {
        "full_name": "John Doe",
        "phone_number": "9876543210",
        "password": "SecurePass123"
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({"error": "Request body is required"}), 400
        
        full_name = data.get("full_name", "").strip()
        phone_number = data.get("phone_number", "").strip()
        password = data.get("password", "")
        
        result = signup_user(DB_PATH, full_name, phone_number, password)
        status = result.pop("status", 200)
        
        return jsonify(result), status
        
    except Exception as e:
        return jsonify({"error": f"Server error: {str(e)}"}), 500


@app.route("/api/auth/login", methods=["POST"])
@limiter.limit("10 per minute")  # Limit login attempts
def api_login():
    """
    Authenticate a user and return JWT token.
    
    Request JSON:
    {
        "phone_number": "9876543210",
        "password": "SecurePass123"
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({"error": "Request body is required"}), 400
        
        phone_number = data.get("phone_number", "").strip()
        password = data.get("password", "")
        
        result = login_user(DB_PATH, phone_number, password)
        status = result.pop("status", 200)
        
        return jsonify(result), status
        
    except Exception as e:
        return jsonify({"error": f"Server error: {str(e)}"}), 500


@app.route("/api/auth/verify", methods=["GET"])
@token_required
def api_verify_token():
    """
    Verify if the current token is valid.
    Protected route that requires JWT token in Authorization header.
    """
    try:
        user_data = get_user_by_id(DB_PATH, request.current_user['user_id'])
        if user_data:
            return jsonify({"valid": True, "user": user_data}), 200
        else:
            return jsonify({"error": "User not found"}), 404
    except Exception as e:
        return jsonify({"error": f"Server error: {str(e)}"}), 500


@app.route("/api/user/profile", methods=["GET"])
@token_required
def api_get_profile():
    """
    Get current user profile.
    Protected route - requires JWT token.
    """
    try:
        user_data = get_user_by_id(DB_PATH, request.current_user['user_id'])
        if user_data:
            return jsonify(user_data), 200
        else:
            return jsonify({"error": "User not found"}), 404
    except Exception as e:
        return jsonify({"error": f"Server error: {str(e)}"}), 500


@app.route("/api/user/preferences", methods=["POST"])
@token_required
def api_update_preferences():
    """
    Update user preferences (e.g., language).
    Protected route - requires JWT token.
    """
    try:
        user_id = request.current_user['user_id']
        data = request.get_json()
        
        if not data:
            return jsonify({"error": "Request body is required"}), 400
        
        preferred_language = data.get('preferred_language')
        
        # Validate language
        valid_languages = ['english', 'hindi', 'telugu']
        if preferred_language and preferred_language not in valid_languages:
            return jsonify({"error": f"Invalid language. Must be one of: {', '.join(valid_languages)}"}), 400
        
        # Update database
        conn = get_db_connection(DB_PATH)
        cursor = conn.cursor()
        
        if preferred_language:
            cursor.execute(
                "UPDATE users SET preferred_language = ? WHERE id = ?",
                (preferred_language, user_id)
            )
        
        conn.commit()
        conn.close()
        
        return jsonify({
            "message": "Preferences updated successfully",
            "preferred_language": preferred_language
        }), 200
        
    except Exception as e:
        return jsonify({"error": f"Server error: {str(e)}"}), 500


# ------------------------------------------
# Survey and Prediction Routes
# ------------------------------------------

@app.route("/survey/questions", methods=["GET"])
def get_survey_questions():
    """
    Returns all survey questions for the guided form.
    Frontend can use this to build multi-slide survey UI.
    
    Response format:
    {
        "total_questions": 15,
        "questions": [
            {
                "id": 1,
                "field_name": "age",
                "question": "What is your age?",
                "type": "number_input",
                "options": [],
                "help_text": "...",
                "required": true
            },
            ...
        ]
    }
    """
    return jsonify({
        "total_questions": len(SURVEY_QUESTIONS),
        "questions": SURVEY_QUESTIONS,
    })


@app.route("/survey/submit", methods=["POST"])
@limiter.limit("5 per minute", key_func=_rate_limit_key)
def submit_survey():
    """
    Accepts completed survey form and returns risk assessment.
    Expects a JSON body with the survey answers.
    
    Example request:
    {
        "survey_data": {
            "age": 60,
            "gender": "Female",
            "height_feet": 5,
            "height_inches": 6,
            "weight_kg": 70,
            "calcium_frequency": "Daily",
            "memory_issue": "No",
            ...
        }
    }
    """
    key_err = _require_api_key()
    if key_err:
        return key_err
    user_id, user_err = _require_user_id()
    if user_err:
        return user_err
    
    try:
        model, feature_order = _load_artifacts()
    except Exception as exc:
        return jsonify({"error": str(exc)}), 503
    
    data = _parse_json_payload()
    if not data or "survey_data" not in data:
        return jsonify({"error": "Request must include 'survey_data' field"}), 400

    local_id = data.get("local_id")
    ok_local_id, local_id_msg = _validate_local_id(local_id)
    if not ok_local_id:
        return jsonify({"error": local_id_msg}), 400

    timestamp = data.get("timestamp")
    if timestamp is not None and (not isinstance(timestamp, str) or not _is_valid_iso_datetime(timestamp)):
        return jsonify({"error": "timestamp must be ISO-8601 format"}), 400

    schema_version = data.get("schema_version", 1)
    if not isinstance(schema_version, int) or schema_version < 1 or schema_version > SYNC_SCHEMA_VERSION:
        return jsonify({"error": f"Unsupported schema_version: {schema_version}"}), 400

    request_time_slot = str(data.get("time_slot", "")).strip().lower()
    if request_time_slot and request_time_slot not in {"morning", "afternoon", "evening"}:
        request_time_slot = ""

    request_shap_values = data.get("shap_values")
    
    survey_data = data["survey_data"]
    
    # Validate required fields
    ok, msg = _validate_form_input(survey_data)
    if not ok:
        return jsonify({"error": f"Invalid input: {msg}"}), 400
    
    try:
        # Prepare feature vector from survey data
        X = _prepare_frame_from_forms([survey_data], feature_order)
        
        # Make prediction
        threshold_val = float(data.get("threshold", 0.1))
        prob = model.predict_proba(X)[:, 1]
        pred = (prob >= threshold_val).astype(int)
        risk_level = _risk_level(prob[0])
        next_reassessment_date = _compute_next_reassessment_date(risk_level)
        message = _risk_message(risk_level)
        reminder_bundle = _generate_tasks_bundle(
            survey_data,
            user_id=user_id,
            risk_level=risk_level,
            shap_values=request_shap_values if isinstance(request_shap_values, dict) else None,
            current_slot=request_time_slot or None,
            probability=float(prob[0]),
        )
        tasks = list(reminder_bundle.get("tasks", []))
        matched_tags = list(reminder_bundle.get("matched_tags", []))
        top_factors = list(reminder_bundle.get("top_factors", []))
        top_factors_with_weight = list(reminder_bundle.get("top_factors_with_weight", []))
        factor_task_link = dict(reminder_bundle.get("factor_task_link", {}))
        primary_action = str(reminder_bundle.get("primary_action", ""))
        time_groups = dict(reminder_bundle.get("time_groups", {}))
        type_groups = dict(reminder_bundle.get("type_groups", {}))
        confidence = float(reminder_bundle.get("confidence", 0.0))
        confidence_label = str(reminder_bundle.get("confidence_label", _get_confidence_label(confidence)))
        confidence_band = str(reminder_bundle.get("confidence_band", _get_confidence_band(confidence)))
        confidence_reason = str(reminder_bundle.get("confidence_reason", ""))
        confidence_note = str(reminder_bundle.get("confidence_note", _get_confidence_note(risk_level, confidence)))
        urgency = _urgency_from_risk(risk_level)
        alerts = _medical_alerts(survey_data)
        
    except Exception as exc:
        return jsonify({"error": f"Inference failed: {exc}"}), 400
    
    response_body = {
        "prediction": int(pred[0]),
        "probability": float(prob[0]),
        "risk_level": risk_level,
        "risk_score": int(round(float(prob[0]) * 100)),
        "next_reassessment_date": next_reassessment_date,
        "message": message,
        "urgency": urgency,
        "confidence": confidence,
        "confidence_label": confidence_label,
        "confidence_band": confidence_band,
        "confidence_reason": confidence_reason,
        "confidence_note": confidence_note,
        "recommended_tasks": tasks,
        "matched_tags": matched_tags,
        "top_factors": top_factors,
        "top_factors_with_weight": top_factors_with_weight,
        "factor_task_link": factor_task_link,
        "primary_action": primary_action,
        "time_groups": time_groups,
        "type_groups": type_groups,
        "medical_alerts": alerts,
        "model_version": MODEL_VERSION,
        "schema_version": schema_version,
    }
    
    # Save to history
    _save_prediction(user_id, "survey_submit", {
        "prediction": int(pred[0]),
        "probability": float(prob[0]),
        "inputs": survey_data,
    })

    # Save latest risk snapshot for dashboard/reassessment timeline
    _save_risk_assessment(
        user_id=user_id,
        risk_score=float(prob[0]) * 100.0,
        risk_level=risk_level,
        next_reassessment_date=next_reassessment_date,
    )

    _upsert_mongo_submission(user_id, local_id, {
        "user_id": user_id,
        "local_id": local_id,
        "timestamp": timestamp,
        "source": "survey_submit",
        "model_version": MODEL_VERSION,
        "schema_version": schema_version,
        "survey_data": survey_data,
        "prediction": {
            "prediction": int(pred[0]),
            "probability": float(prob[0]),
            "risk_level": risk_level,
            "urgency": urgency,
            "confidence": confidence,
            "confidence_label": confidence_label,
            "confidence_band": confidence_band,
            "confidence_reason": confidence_reason,
            "confidence_note": confidence_note,
            "risk_score": int(round(float(prob[0]) * 100)),
            "next_reassessment_date": next_reassessment_date,
            "recommended_tasks": tasks,
            "matched_tags": matched_tags,
            "top_factors": top_factors,
            "top_factors_with_weight": top_factors_with_weight,
            "factor_task_link": factor_task_link,
            "primary_action": primary_action,
            "time_groups": time_groups,
            "type_groups": type_groups,
            "medical_alerts": alerts,
        },
        "created_at": datetime.utcnow().isoformat(),
    })
    
    return jsonify(response_body)


@app.route("/history", methods=["GET"])
@limiter.limit("5 per minute", key_func=_rate_limit_key)
def history():
    key_err = _require_api_key()
    if key_err:
        return key_err
    user_id, user_err = _require_user_id()
    if user_err:
        return user_err
    try:
        limit = int(request.args.get("limit", 50))
    except Exception:
        limit = 50
    limit = max(1, min(limit, 200))
    history_rows = _get_history(user_id, limit)
    return jsonify({"history": history_rows, "count": len(history_rows)})


@app.route("/save", methods=["POST"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def save_data():
    """API bridge endpoint for app-to-cloud record persistence."""
    _tick_request_window()
    chaos_err = _maybe_inject_sync_chaos()
    if chaos_err:
        return chaos_err
    is_backpressure, retry_after = _should_apply_backpressure()
    if is_backpressure:
        response = jsonify({"error": "Server busy", "retry_after": retry_after})
        response.status_code = 429
        response.headers["Retry-After"] = str(retry_after)
        return response

    paused_err = _reject_if_writes_paused()
    if paused_err:
        return paused_err

    raw_body = request.get_data(cache=True) or b""
    user_id, user_err = _require_sync_security(raw_body)
    if user_err:
        return user_err

    payload = _parse_json_payload()
    if not isinstance(payload, dict):
        return jsonify({"error": "Request body must be a JSON object"}), 400

    contract, contract_err = _extract_group_contract(payload, user_id)
    if contract_err:
        return contract_err

    _sync_metrics["single_requests"] += 1
    _sync_metrics["records_received"] += 1

    ok, msg = _validate_cloud_record(payload)
    if not ok:
        _record_sync_failure(msg)
        return jsonify({"error": msg}), 400

    local_id = payload.get("local_id")

    saved = _upsert_mongo_submission(user_id, local_id, {
        "user_id": user_id,
        "local_id": local_id,
        "sync_group_id": contract.get("sync_group_id") if contract else None,
        "sync_group_expected_count": contract.get("sync_group_expected_count") if contract else None,
        "sync_group_version": contract.get("sync_group_version") if contract else None,
        "timestamp": payload.get("timestamp"),
        "source": "save_endpoint",
        "model_version": payload.get("model_version") or MODEL_VERSION,
        "payload": payload,
        "created_at": datetime.utcnow().isoformat(),
    })
    if not saved:
        _record_sync_failure("mongo_unavailable")
        return jsonify({"error": "MongoDB unavailable"}), 503

    _sync_metrics["records_synced"] += 1
    _send_sync_alerts_if_needed()

    if _chaos_mode_triggered("ack_drop"):
        g.sync_chaos_injected_failure = True
        return jsonify({"error": "Chaos ack_drop: write persisted but ack lost"}), 503

    if _chaos_mode_triggered("inconsistent_response"):
        return jsonify({
            "status": "partial_success",
            "synced_local_ids": [],
            "failed_local_ids": [local_id],
            "note": "chaos_inconsistent_response",
        }), 200

    return jsonify({"status": "success"}), 200


@app.route("/save/status", methods=["POST"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def save_status():
    _tick_request_window()
    chaos_err = _maybe_inject_sync_chaos()
    if chaos_err:
        return chaos_err
    is_backpressure, retry_after = _should_apply_backpressure()
    if is_backpressure:
        response = jsonify({"error": "Server busy", "retry_after": retry_after})
        response.status_code = 429
        response.headers["Retry-After"] = str(retry_after)
        return response

    raw_body = request.get_data(cache=True) or b""
    user_id, user_err = _require_sync_security(raw_body)
    if user_err:
        return user_err

    payload = _parse_json_payload()
    if not isinstance(payload, dict):
        return jsonify({"error": "Request body must be a JSON object"}), 400

    local_ids = payload.get("local_ids")
    if not isinstance(local_ids, list):
        return jsonify({"error": "'local_ids' must be a list"}), 400
    if len(local_ids) > 200:
        return jsonify({"error": "Too many ids (max 200)"}), 400

    normalized_ids = [x.strip() for x in local_ids if isinstance(x, str) and x.strip()]
    if not normalized_ids:
        return jsonify({"existing_local_ids": []}), 200

    collection = _get_mongo_collection()
    if collection is None:
        return jsonify({"error": "MongoDB unavailable"}), 503

    _sync_metrics["status_checks"] += 1

    rows = collection.find(
        {
            "user_id": user_id,
            "local_id": {"$in": normalized_ids},
            "server_created_at_dt": {"$gt": _retention_cutoff_dt()},
        },
        {"_id": 0, "local_id": 1},
    )
    existing = [row.get("local_id") for row in rows if isinstance(row.get("local_id"), str)]

    return jsonify({"existing_local_ids": existing}), 200


@app.route("/save/batch", methods=["POST"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def save_data_batch():
    _tick_request_window()
    chaos_err = _maybe_inject_sync_chaos()
    if chaos_err:
        return chaos_err
    is_backpressure, retry_after = _should_apply_backpressure()
    if is_backpressure:
        response = jsonify({"error": "Server busy", "retry_after": retry_after})
        response.status_code = 429
        response.headers["Retry-After"] = str(retry_after)
        return response

    paused_err = _reject_if_writes_paused()
    if paused_err:
        return paused_err

    raw_body = request.get_data(cache=True) or b""
    user_id, user_err = _require_sync_security(raw_body)
    if user_err:
        return user_err

    payload = _parse_json_payload()
    if not isinstance(payload, dict):
        return jsonify({"error": "Request body must be a JSON object"}), 400

    contract, contract_err = _extract_group_contract(payload, user_id)
    if contract_err:
        return contract_err

    request_schema_version = payload.get("schema_version", 1)
    if not isinstance(request_schema_version, int) or request_schema_version < 1 or request_schema_version > SYNC_SCHEMA_VERSION:
        return jsonify({"error": f"Unsupported schema_version: {request_schema_version}"}), 400

    records = payload.get("records")
    if not isinstance(records, list) or not records:
        return jsonify({"error": "'records' must be a non-empty list"}), 400
    if len(records) > 50:
        return jsonify({"error": "Batch too large (max 50 records)"}), 400

    batch_hash = payload.get("batch_hash")
    batch_ok, batch_msg = _verify_batch_hash(records, batch_hash)
    if not batch_ok:
        _record_sync_failure(batch_msg)
        return jsonify({"error": batch_msg}), 400

    _sync_metrics["batch_requests"] += 1
    _sync_metrics["records_received"] += len(records)

    synced_local_ids: list[str] = []
    failed_local_ids: list[str] = []
    failed_details: list[dict] = []

    for item in records:
        if not isinstance(item, dict):
            failed_local_ids.append("")
            failed_details.append({"local_id": "", "reason": "record_not_object"})
            _record_sync_failure("record_not_object")
            continue

        ok, msg = _validate_cloud_record(item)
        local_id = item.get("local_id") if isinstance(item.get("local_id"), str) else ""
        if not ok:
            app.logger.warning("Rejected batch record local_id=%s: %s", local_id, msg)
            failed_local_ids.append(local_id)
            failed_details.append({"local_id": local_id, "reason": msg})
            _record_sync_failure(msg)
            continue

        if _chaos_mode_enabled("partial_write") and random.random() < max(0.0, min(1.0, SYNC_CHAOS_PARTIAL_WRITE_DROP_RATE)):
            g.sync_chaos_injected_failure = True
            failed_local_ids.append(local_id)
            failed_details.append({"local_id": local_id, "reason": "chaos_partial_write_drop"})
            _record_sync_failure("chaos_partial_write_drop")
            continue

        saved = _upsert_mongo_submission(user_id, local_id, {
            "user_id": user_id,
            "local_id": local_id,
            "sync_group_id": contract.get("sync_group_id") if contract else None,
            "sync_group_expected_count": contract.get("sync_group_expected_count") if contract else None,
            "sync_group_version": contract.get("sync_group_version") if contract else None,
            "timestamp": item.get("timestamp"),
            "source": "save_batch",
            "model_version": item.get("model_version") or MODEL_VERSION,
            "survey_data": item.get("survey_data"),
            "payload": item,
            "created_at": datetime.utcnow().isoformat(),
        })
        if saved:
            synced_local_ids.append(local_id)
            _sync_metrics["records_synced"] += 1
            _send_sync_alerts_if_needed()
        else:
            failed_local_ids.append(local_id)
            failed_details.append({"local_id": local_id, "reason": "mongo_unavailable"})
            _record_sync_failure("mongo_unavailable")

    status_code = 200 if not failed_local_ids else 207
    if _chaos_mode_triggered("ack_drop") and synced_local_ids:
        g.sync_chaos_injected_failure = True
        response = jsonify({"error": "Chaos ack_drop: writes persisted but ack lost"})
        response.status_code = 503
        response.headers["Retry-After"] = str(SYNC_BACKPRESSURE_RETRY_AFTER_SECONDS)
        return response

    if _chaos_mode_triggered("inconsistent_response") and synced_local_ids:
        fake_failed = synced_local_ids[:1]
        response = jsonify({
            "status": "partial_success",
            "synced_local_ids": [],
            "failed_local_ids": fake_failed,
            "failed_details": [{"local_id": fake_failed[0], "reason": "chaos_inconsistent_response"}],
            "retry_after": SYNC_BACKPRESSURE_RETRY_AFTER_SECONDS,
        })
        response.status_code = 200
        return response

    response = jsonify({
        "status": "success" if not failed_local_ids else "partial_success",
        "synced_local_ids": synced_local_ids,
        "failed_local_ids": failed_local_ids,
        "failed_details": failed_details,
        "retry_after": SYNC_BACKPRESSURE_RETRY_AFTER_SECONDS if failed_local_ids else 0,
    })
    response.status_code = status_code
    if failed_local_ids:
        response.headers["Retry-After"] = str(SYNC_BACKPRESSURE_RETRY_AFTER_SECONDS)
    return response


@app.route("/sync/metrics", methods=["GET"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def sync_metrics():
    key_err = _require_api_key()
    if key_err:
        return key_err

    total = _sync_metrics["records_received"]
    synced = _sync_metrics["records_synced"]
    success_rate = (synced / total) if total > 0 else 0.0
    alerts = _compute_sync_alerts()
    chaos_corr = _sync_metrics.get("chaos_correlation", {})

    chaos_requests = int(chaos_corr.get("chaos_requests", 0) or 0)
    non_chaos_requests = int(chaos_corr.get("non_chaos_requests", 0) or 0)
    chaos_success = int(chaos_corr.get("chaos_success", 0) or 0)
    non_chaos_success = int(chaos_corr.get("non_chaos_success", 0) or 0)
    chaos_latency_total = float(chaos_corr.get("chaos_latency_ms_total", 0.0) or 0.0)
    non_chaos_latency_total = float(chaos_corr.get("non_chaos_latency_ms_total", 0.0) or 0.0)

    chaos_success_rate = (chaos_success / chaos_requests) if chaos_requests > 0 else None
    non_chaos_success_rate = (non_chaos_success / non_chaos_requests) if non_chaos_requests > 0 else None
    chaos_avg_latency = (chaos_latency_total / chaos_requests) if chaos_requests > 0 else None
    non_chaos_avg_latency = (non_chaos_latency_total / non_chaos_requests) if non_chaos_requests > 0 else None

    return jsonify({
        "schema_version": SYNC_SCHEMA_VERSION,
        "model_version": MODEL_VERSION,
        "supported_signature_versions": sorted(list(SYNC_SIGNING_KEYS.keys())),
        "metrics": _sync_metrics,
        "success_rate": round(success_rate, 4),
        "chaos_correlation_summary": {
            "chaos_fail_rate_config": SYNC_CHAOS_FAIL_RATE,
            "chaos_delay_ms_config": SYNC_CHAOS_DELAY_MS,
            "chaos_requests": chaos_requests,
            "non_chaos_requests": non_chaos_requests,
            "chaos_success_rate": round(chaos_success_rate, 4) if chaos_success_rate is not None else None,
            "non_chaos_success_rate": round(non_chaos_success_rate, 4) if non_chaos_success_rate is not None else None,
            "success_rate_delta": (
                round((chaos_success_rate - non_chaos_success_rate), 4)
                if chaos_success_rate is not None and non_chaos_success_rate is not None
                else None
            ),
            "chaos_avg_latency_ms": round(chaos_avg_latency, 2) if chaos_avg_latency is not None else None,
            "non_chaos_avg_latency_ms": round(non_chaos_avg_latency, 2) if non_chaos_avg_latency is not None else None,
            "latency_delta_ms": (
                round((chaos_avg_latency - non_chaos_avg_latency), 2)
                if chaos_avg_latency is not None and non_chaos_avg_latency is not None
                else None
            ),
            "chaos_injected_failures": int(chaos_corr.get("chaos_injected_failures", 0) or 0),
            "backpressure_rejections": int(_sync_metrics.get("backpressure_rejections", 0) or 0),
        },
        "cursor_summary": {
            "cursor_submissions": int(_sync_metrics.get("cursor_submissions", 0) or 0),
            "cursor_regressions": int(_sync_metrics.get("cursor_regressions", 0) or 0),
            "cursor_regression_rate": round(
                (int(_sync_metrics.get("cursor_regressions", 0) or 0) / max(1, int(_sync_metrics.get("cursor_submissions", 0) or 0))),
                4,
            ),
            "server_cursor_state_users": len(_sync_cursor_state),
        },
        "alerts": alerts,
    }), 200


@app.route("/sync/group/start", methods=["POST"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def sync_group_start():
    raw_body = request.get_data(cache=True) or b""
    user_id, user_err = _require_sync_security(raw_body)
    if user_err:
        return user_err

    payload = _parse_json_payload() or {}
    requested_expected_count = payload.get("expected_count")
    if not isinstance(requested_expected_count, int):
        return jsonify({"error": "expected_count must be an integer"}), 400

    if requested_expected_count < 1 or requested_expected_count > SYNC_GROUP_MAX_EXPECTED_COUNT:
        return jsonify({
            "error": f"expected_count out of range (1..{SYNC_GROUP_MAX_EXPECTED_COUNT})",
        }), 400

    now_ts = int(time.time())
    token_payload = {
        "v": 1,
        "uid": user_id,
        "gid": f"grp_{uuid.uuid4().hex}",
        "ec": requested_expected_count,
        "gv": 1,
        "iat": now_ts,
        "exp": now_ts + max(60, SYNC_GROUP_CONTRACT_TTL_SECONDS),
    }
    group_token = _encode_group_contract_token(token_payload)
    return jsonify({
        "group_token": group_token,
        "sync_group_id": token_payload["gid"],
        "expected_count": token_payload["ec"],
        "group_version": token_payload["gv"],
        "expires_at": token_payload["exp"],
    }), 200


@app.route("/sync/chaos/gate", methods=["GET"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def sync_chaos_gate():
    key_err = _require_api_key()
    if key_err:
        return key_err

    try:
        min_samples = int(request.args.get("min_samples", str(SYNC_CHAOS_GATE_MIN_SAMPLES)))
    except Exception:
        min_samples = SYNC_CHAOS_GATE_MIN_SAMPLES
    try:
        max_success_drop = float(request.args.get("max_success_drop", str(SYNC_CHAOS_GATE_MAX_SUCCESS_DROP)))
    except Exception:
        max_success_drop = SYNC_CHAOS_GATE_MAX_SUCCESS_DROP
    try:
        max_latency_increase_ratio = float(
            request.args.get("max_latency_increase_ratio", str(SYNC_CHAOS_GATE_MAX_LATENCY_INCREASE_RATIO))
        )
    except Exception:
        max_latency_increase_ratio = SYNC_CHAOS_GATE_MAX_LATENCY_INCREASE_RATIO

    result = _evaluate_chaos_gate(
        min_samples=max(1, min_samples),
        max_success_drop=max(0.0, max_success_drop),
        max_latency_increase_ratio=max(0.0, max_latency_increase_ratio),
    )

    status_code = 200 if result.get("passed") else 412
    return jsonify(result), status_code


@app.route("/sync/alerts", methods=["GET"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def sync_alerts():
    key_err = _require_api_key()
    if key_err:
        return key_err

    return jsonify({"alerts": _compute_sync_alerts()}), 200


@app.route("/reminder/config", methods=["POST"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def reminder_save_config():
    key_err = _require_api_key()
    if key_err:
        return key_err

    user_id, user_err = _require_user_id()
    if user_err:
        return user_err

    payload = _parse_json_payload() or {}
    reminder_time = str(payload.get("reminder_time", "08:00")).strip()
    if not _is_valid_reminder_time(reminder_time):
        return jsonify({"error": "reminder_time must be HH:MM (24h)"}), 400

    enabled = payload.get("enabled", True)
    if not isinstance(enabled, bool):
        return jsonify({"error": "enabled must be boolean"}), 400

    risk_level_raw = str(payload.get("risk_level", "")).strip().upper()
    valid_risk_levels = {"LOW", "MODERATE", "HIGH"}
    if risk_level_raw not in valid_risk_levels:
        return jsonify({"error": "risk_level must be LOW, MODERATE, or HIGH"}), 400
    risk_level = risk_level_raw

    age_group = str(payload.get("age_group", "18-50")).strip() or "18-50"
    if age_group not in {"18-50", "51+"}:
        return jsonify({"error": "age_group must be 18-50 or 51+"}), 400

    reminder_slots = payload.get("reminder_slots", ["morning"])
    if not isinstance(reminder_slots, list):
        return jsonify({"error": "reminder_slots must be a list"}), 400
    normalized_slots = [
        str(slot).strip().lower()
        for slot in reminder_slots
        if str(slot).strip().lower() in {"morning", "afternoon", "evening"}
    ]
    if not normalized_slots:
        normalized_slots = ["morning"]

    collection = _get_mongo_reminder_config_collection()
    if collection is None:
        return jsonify({"error": "MongoDB unavailable"}), 503

    now_iso = datetime.utcnow().isoformat()
    collection.update_one(
        {"user_id": user_id},
        {
            "$set": {
                "user_id": user_id,
                "age_group": age_group,
                "risk_level": risk_level,
                "reminder_time": reminder_time,
                "enabled": enabled,
                "reminder_slots": normalized_slots,
                "updated_at": now_iso,
            },
            "$setOnInsert": {
                "created_at": now_iso,
            },
        },
        upsert=True,
    )

    return jsonify({
        "status": "saved",
        "config": {
            "user_id": user_id,
            "age_group": age_group,
            "risk_level": risk_level,
            "reminder_time": reminder_time,
            "enabled": enabled,
            "reminder_slots": normalized_slots,
        },
    }), 200


@app.route("/reminder/get", methods=["GET"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def reminder_get_config():
    key_err = _require_api_key()
    if key_err:
        return key_err

    user_id = request.args.get("user_id", "").strip() or request.headers.get("X-User-Id", "").strip()
    if not user_id:
        return jsonify({"error": "Missing user id"}), 401

    collection = _get_mongo_reminder_config_collection()
    if collection is None:
        return jsonify({"error": "MongoDB unavailable"}), 503

    config = collection.find_one({"user_id": user_id}, {"_id": 0})
    if config is None:
        return jsonify({
            "status": "not_found",
            "config": {
                "user_id": user_id,
                "age_group": "18-50",
                "risk_level": "MODERATE",
                "reminder_time": "08:00",
                "enabled": True,
                "reminder_slots": ["morning"],
            },
        }), 200

    return jsonify({"status": "ok", "config": config}), 200


@app.route("/reminder/habit", methods=["POST"])
@limiter.limit("60 per minute", key_func=_rate_limit_key)
def reminder_habit_log():
    key_err = _require_api_key()
    if key_err:
        return key_err

    user_id, user_err = _require_user_id()
    if user_err:
        return user_err

    payload = _parse_json_payload() or {}
    tip = str(payload.get("tip", "")).strip()
    if not tip:
        return jsonify({"error": "tip is required"}), 400

    completed = bool(payload.get("completed", False))
    date_raw = str(payload.get("date", datetime.utcnow().date().isoformat())).strip()

    history_collection = _get_mongo_reminder_history_collection()
    if history_collection is None:
        return jsonify({"error": "MongoDB unavailable"}), 503

    history_collection.insert_one({
        "user_id": user_id,
        "tip": tip,
        "completed": completed,
        "date": date_raw,
        "created_at": datetime.utcnow().isoformat(),
    })

    return jsonify({"status": "logged"}), 200


@app.route("/sync/export", methods=["GET"])
@limiter.limit("10 per minute", key_func=_rate_limit_key)
def sync_export():
    admin_err = _require_admin_export_access()
    if admin_err:
        return admin_err

    collection = _get_mongo_collection()
    if collection is None:
        return jsonify({"error": "MongoDB unavailable"}), 503

    try:
        days = int(request.args.get("days", str(max(1, SYNC_RETENTION_DAYS))))
    except Exception:
        days = max(1, SYNC_RETENTION_DAYS)
    days = max(1, min(days, 3650))

    cutoff = datetime.utcnow() - timedelta(days=days)
    cursor = collection.find(
        {"server_created_at_dt": {"$gte": cutoff}},
        {"_id": 0},
    )

    records = list(cursor)
    _audit_sync_event("sync_export", {"days": days, "count": len(records)})
    return jsonify({
        "exported_at": datetime.utcnow().isoformat(),
        "days": days,
        "count": len(records),
        "records": records,
    }), 200


@app.route("/sync/backup/manifest", methods=["GET"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def sync_backup_manifest():
    admin_err = _require_admin_export_access()
    if admin_err:
        return admin_err

    collection = _get_mongo_collection()
    if collection is None:
        return jsonify({"error": "MongoDB unavailable"}), 503

    total = collection.count_documents({})
    recent = collection.count_documents({"server_created_at_dt": {"$gte": _retention_cutoff_dt()}})
    return jsonify({
        "total_documents": total,
        "retained_documents": recent,
        "retention_days": SYNC_RETENTION_DAYS,
        "generated_at": datetime.utcnow().isoformat(),
        "recommended_action": "Call /sync/export regularly and store outputs in durable object storage.",
    }), 200


@app.route("/sync/backup/run", methods=["POST"])
@limiter.limit("5 per minute", key_func=_rate_limit_key)
def sync_backup_run():
    admin_err = _require_admin_export_access()
    if admin_err:
        return admin_err

    payload = _parse_json_payload() or {}
    try:
        days = int(payload.get("days", max(1, SYNC_RETENTION_DAYS)))
    except Exception:
        days = max(1, SYNC_RETENTION_DAYS)
    days = max(1, min(days, 3650))

    try:
        path = _run_sync_backup_to_file(days=days)
    except Exception as exc:
        return jsonify({"error": str(exc)}), 503

    return jsonify({
        "status": "ok",
        "path": path,
        "days": days,
    }), 200


@app.route("/sync/pull", methods=["POST"])
@limiter.limit("30 per minute", key_func=_rate_limit_key)
def sync_pull():
    _tick_request_window()
    chaos_err = _maybe_inject_sync_chaos()
    if chaos_err:
        return chaos_err

    is_backpressure, retry_after = _should_apply_backpressure()
    if is_backpressure:
        response = jsonify({"error": "Server busy", "retry_after": retry_after})
        response.status_code = 429
        response.headers["Retry-After"] = str(retry_after)
        return response

    raw_body = request.get_data(cache=True) or b""
    user_id, user_err = _require_sync_security(raw_body)
    if user_err:
        return user_err

    payload = _parse_json_payload() or {}
    try:
        limit = int(payload.get("limit", SYNC_PULL_DEFAULT_LIMIT))
    except Exception:
        limit = SYNC_PULL_DEFAULT_LIMIT
    limit = max(1, min(limit, max(1, SYNC_PULL_MAX_LIMIT)))

    try:
        max_response_bytes = int(payload.get("max_response_bytes", SYNC_PULL_MAX_RESPONSE_BYTES))
    except Exception:
        max_response_bytes = SYNC_PULL_MAX_RESPONSE_BYTES
    max_response_bytes = max(64 * 1024, min(max_response_bytes, max(64 * 1024, SYNC_PULL_MAX_RESPONSE_BYTES)))

    since = payload.get("since")
    cursor_raw = payload.get("cursor")
    cursor_echo = cursor_raw if isinstance(cursor_raw, str) and cursor_raw.strip() else None
    cursor_created_at, cursor_local_id = _decode_pull_cursor(cursor_raw)
    if cursor_raw is not None and cursor_created_at is None:
        return jsonify({"error": "Invalid cursor"}), 400
    if cursor_created_at is not None:
        _sync_metrics["cursor_submissions"] = int(_sync_metrics.get("cursor_submissions", 0) or 0) + 1
        if _is_cursor_regression(user_id, cursor_created_at, cursor_local_id):
            _sync_metrics["cursor_regressions"] = int(_sync_metrics.get("cursor_regressions", 0) or 0) + 1
            _record_sync_failure("cursor_regression")
            return jsonify({"error": "Cursor regression rejected"}), 409
    filter_query = {
        "user_id": user_id,
        "server_created_at_dt": {"$gt": _retention_cutoff_dt()},
    }
    if cursor_created_at is not None:
        filter_query["$or"] = [
            {"server_created_at": {"$gt": cursor_created_at}},
            {
                "server_created_at": cursor_created_at,
                "local_id": {"$gt": cursor_local_id},
            },
        ]
    elif isinstance(since, str) and _is_valid_iso_datetime(since):
        filter_query["server_created_at"] = {"$gt": since}

    include_payload = bool(payload.get("include_payload", True))
    projection = {"_id": 0}
    if not include_payload:
        projection["payload"] = 0

    collection = _get_mongo_collection()
    if collection is None:
        return jsonify({"error": "MongoDB unavailable"}), 503

    try:
        rows_raw = list(
            collection.find(filter_query, projection)
            .sort([("server_created_at", 1), ("local_id", 1)])
            .limit(limit + 1)
            .max_time_ms(max(250, SYNC_PULL_MAX_TIME_MS))
        )
    except Exception as exc:
        return jsonify({"error": f"sync pull query failed: {exc}"}), 503

    has_more = len(rows_raw) > limit
    rows = rows_raw[:limit]

    selected_rows: list[dict] = []
    estimated_response_bytes = 2
    for row in rows:
        row_json = json.dumps(row, separators=(",", ":"), ensure_ascii=False)
        row_size = len(row_json.encode("utf-8"))
        extra_sep = 1 if selected_rows else 0

        if selected_rows and (estimated_response_bytes + extra_sep + row_size > max_response_bytes):
            has_more = True
            break

        if not selected_rows and row_size > max_response_bytes:
            return jsonify({
                "error": "Single record exceeds max_response_bytes; retry with include_payload=false or larger limit on server config",
            }), 413

        selected_rows.append(row)
        estimated_response_bytes += extra_sep + row_size

    if len(selected_rows) < len(rows):
        has_more = True

    next_cursor = None
    if has_more and selected_rows:
        last = selected_rows[-1]
        next_cursor = _encode_pull_cursor(
            str(last.get("server_created_at", "")),
            str(last.get("local_id", "")),
        )

    resume_cursor = _current_or_next_cursor(
        cursor_created_at or "",
        cursor_local_id,
        selected_rows,
        next_cursor,
    )
    resume_created_at, resume_local_id = _decode_pull_cursor(resume_cursor)
    if resume_created_at is not None:
        _update_cursor_state(user_id, resume_created_at, resume_local_id)

    return jsonify({
        "records": selected_rows,
        "count": len(selected_rows),
        "next_cursor": next_cursor,
        "resume_cursor": resume_cursor,
        "cursor_echo": cursor_echo,
        "has_more": has_more,
        "limit_applied": limit,
        "max_response_bytes": max_response_bytes,
        "estimated_response_bytes": estimated_response_bytes,
    }), 200


def _load_artifacts():
    global _model, _feature_order
    if _model is None:
        if not os.path.exists(MODEL_PATH):
            raise FileNotFoundError(
                f"Model file not found at {MODEL_PATH}. Export it from the notebook or copy it to backend/artifacts/."
            )
        app.logger.info("Loading model from %s", MODEL_PATH)
        _model = joblib.load(MODEL_PATH)
    if _feature_order is None:
        if not os.path.exists(FEATURES_PATH):
            raise FileNotFoundError(
                f"Feature list not found at {FEATURES_PATH}. Save the ordered feature names alongside the model."
            )
        app.logger.info("Loading feature order from %s", FEATURES_PATH)
        with open(FEATURES_PATH, "r", encoding="utf-8") as f:
            _feature_order = json.load(f)
    return _model, _feature_order


@app.route("/user_data", methods=["DELETE"])
@limiter.limit("5 per minute")
def delete_user_data():
    key_err = _require_api_key()
    if key_err:
        return key_err
    user_id, user_err = _require_user_id()
    if user_err:
        return user_err
    _ensure_predictions_table()
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("DELETE FROM predictions WHERE user_id = ?", (user_id,))
        conn.commit()
    finally:
        conn.close()
    return jsonify({"status": "user data deleted"})


@app.route("/artifacts_check", methods=["GET"])
def artifacts_check():
    return jsonify({
        "model_path": MODEL_PATH,
        "model_exists": os.path.exists(MODEL_PATH),
        "features_path": FEATURES_PATH,
        "features_exists": os.path.exists(FEATURES_PATH)
    })


@app.route("/routes", methods=["GET"])
def routes():
    return jsonify(sorted([str(r) for r in app.url_map.iter_rules()]))


def _prepare_frame(records: list[dict], feature_order: list[str]) -> pd.DataFrame:
    df = pd.DataFrame(records)
    missing = [f for f in feature_order if f not in df.columns]
    if missing:
        raise ValueError(f"Missing features: {missing}")
    # Keep only expected columns and fill the rest
    df = df[feature_order].copy()
    return df.fillna(0)


def _prepare_frame_from_forms(forms: list[dict], feature_order: list[str]) -> pd.DataFrame:
    mapped = [_map_form_entry(entry, feature_order) for entry in forms]
    return pd.DataFrame(mapped)[feature_order].fillna(0)


def _require_api_key():
    if not API_KEY:
        return jsonify({"error": "Server API key not configured. Set API_KEY env var."}), 503

    # Support either Authorization: Bearer <key> or x-api-key: <key>
    auth_header = request.headers.get("Authorization", "")
    token = None
    prefix = "Bearer "
    if auth_header.startswith(prefix):
        token = auth_header[len(prefix):].strip()
    else:
        token = request.headers.get("x-api-key") or request.headers.get("X-API-Key")

    if token != API_KEY:
        return jsonify({"error": "Invalid or missing API key"}), 401
    return None


def _require_user_id() -> tuple[str | None, tuple | None]:
    user_id = request.headers.get("X-User-Id", "").strip()
    if not user_id:
        return None, (jsonify({"error": "Missing user id header 'X-User-Id'"}), 401)
    return user_id, None


def _is_valid_iso_datetime(value: str) -> bool:
    try:
        normalized = value.replace("Z", "+00:00")
        datetime.fromisoformat(normalized)
        return True
    except Exception:
        return False


def _validate_local_id(local_id: str | None) -> tuple[bool, str]:
    if local_id is None:
        return True, ""
    if not isinstance(local_id, str):
        return False, "local_id must be a string"
    trimmed = local_id.strip()
    if not trimmed:
        return False, "local_id cannot be empty"
    if len(trimmed) > 128:
        return False, "local_id too long"
    return True, ""


def _validate_cloud_record(record: dict) -> tuple[bool, str]:
    if not isinstance(record, dict):
        return False, "record must be an object"

    local_id = record.get("local_id")
    if local_id is None:
        return False, "local_id is required"
    ok, msg = _validate_local_id(local_id)
    if not ok:
        return False, msg

    timestamp = record.get("timestamp")
    if timestamp is not None:
        if not isinstance(timestamp, str) or not _is_valid_iso_datetime(timestamp):
            return False, "timestamp must be ISO-8601 format"

    survey_data = record.get("survey_data")
    if survey_data is not None and not isinstance(survey_data, dict):
        return False, "survey_data must be an object"

    hash_ok, hash_msg = _verify_data_hash(record)
    if not hash_ok:
        return False, hash_msg

    schema_version = record.get("schema_version", 1)
    if not isinstance(schema_version, int):
        return False, "schema_version must be an integer"
    if schema_version < 1 or schema_version > SYNC_SCHEMA_VERSION:
        return False, f"Unsupported schema_version: {schema_version}"

    sync_group_id = record.get("sync_group_id")
    if sync_group_id is not None:
        if not isinstance(sync_group_id, str) or not sync_group_id.strip():
            return False, "sync_group_id must be a non-empty string"
        if len(sync_group_id.strip()) > 128:
            return False, "sync_group_id too long"

    sync_group_expected_count = record.get("sync_group_expected_count")
    if sync_group_expected_count is not None:
        if not isinstance(sync_group_expected_count, int):
            return False, "sync_group_expected_count must be an integer"
        if sync_group_expected_count < 1 or sync_group_expected_count > 1000:
            return False, "sync_group_expected_count out of range"

    return True, ""


def _ensure_predictions_table():
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS predictions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                predictions_json TEXT NOT NULL,
                probabilities_json TEXT,
                inputs_json TEXT NOT NULL,
                created_at TEXT DEFAULT (datetime('now'))
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_predictions_user_created ON predictions(user_id, created_at DESC)"
        )
        conn.commit()
    finally:
        conn.close()


def _save_prediction(user_id: str, endpoint: str, payload: dict):
    _ensure_predictions_table()
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            "INSERT INTO predictions (user_id, endpoint, predictions_json, probabilities_json, inputs_json) VALUES (?, ?, ?, ?, ?)",
            (
                user_id,
                endpoint,
                json.dumps(payload.get("predictions", [])),
                json.dumps(payload.get("probabilities")),
                json.dumps(payload.get("inputs", {})),
            ),
        )
        conn.commit()
    finally:
        conn.close()


def _save_risk_assessment(user_id: str, risk_score: float, risk_level: str, next_reassessment_date: str):
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            """
            INSERT INTO risk_assessments (user_id, risk_score, risk_level, next_reassessment_date)
            VALUES (?, ?, ?, ?)
            """,
            (user_id, risk_score, risk_level, next_reassessment_date),
        )
        conn.commit()
    finally:
        conn.close()


def _get_history(user_id: str, limit: int = 50) -> list[dict]:
    _ensure_predictions_table()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            "SELECT id, endpoint, predictions_json, probabilities_json, inputs_json, created_at FROM predictions WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
            (user_id, limit),
        ).fetchall()
        history: list[dict] = []
        for row in rows:
            history.append({
                "id": row["id"],
                "endpoint": row["endpoint"],
                "created_at": row["created_at"],
                "predictions": json.loads(row["predictions_json"] or "[]"),
                "probabilities": json.loads(row["probabilities_json"] or "null"),
                "inputs": json.loads(row["inputs_json"] or "{}"),
            })
        return history
    finally:
        conn.close()


def _validate_record(record: dict) -> tuple[bool, str]:
    try:
        if "RIDAGEYR" in record:
            age = float(record["RIDAGEYR"])
            if age < 18 or age > 100:
                return False, "age must be between 18 and 100"
        if "BMXBMI" in record:
            bmi = float(record["BMXBMI"])
            if bmi < 10 or bmi > 60:
                return False, "BMI must be between 10 and 60"
        bool_like_cols = list(FRIENDLY_BOOL_MAP.keys()) + ["MCQ550", "MCQ025"]
        for col in bool_like_cols:
            if col in record:
                val = record[col]
                if val not in {0, 1, "0", "1"}:
                    return False, f"{col} must be 0 or 1"
        if "RIAGENDR" in record:
            gender_val = int(record["RIAGENDR"])
            if gender_val not in {1, 2}:
                return False, "RIAGENDR must be 1 (male) or 2 (female)"
    except Exception:
        return False, "numeric fields invalid"
    return True, ""


def _parse_iso_date(value: str) -> date | None:
    raw = (value or "").strip()
    if not raw:
        return None
    try:
        return datetime.strptime(raw, "%Y-%m-%d").date()
    except Exception:
        return None


def _validate_form_input(form: dict) -> tuple[bool, str]:
    try:
        age = float(form.get("age", 0))
        if age < 18 or age > 100:
            return False, "age must be between 18 and 100"
        # Convert feet and inches to cm
        feet = form.get("height_feet")
        inches = form.get("height_inches")
        weight = form.get("weight_kg")
        if feet is None or inches is None or weight is None:
            return False, "height (feet and inches) and weight are required"
        feet_val = float(feet)
        inches_val = float(inches)
        weight_val = float(weight)
        # height_cm = (feet * 30.48) + (inches * 2.54)
        height_cm = (feet_val * 30.48) + (inches_val * 2.54)
        bmi = weight_val / ((height_cm / 100) ** 2) if height_cm > 0 else 0
        if bmi < 10 or bmi > 60:
            return False, "BMI must be between 10 and 60"
    except Exception:
        return False, "numeric fields invalid"

    # Yes/No fields with flexible validation
    yes_no_fields = [
        "memory_issue",
        "mobility_climb",
        "stand_long",
        "activity_limited",
        "arthritis",
        "thyroid",
        "lung_disease",
        "heart_failure",
        "smoking",
    ]
    for key in yes_no_fields:
        val = form.get(key, "")
        # Accept boolean (true/false), empty string, or flexible yes/no values
        if isinstance(val, bool):
            continue
        if val is None:
            continue
        val_str = str(val).strip().lower()
        # Accept: empty, yes, no, y, n, true, false, 1, 0, and other flexible variations
        valid_yes_no = {"", "yes", "no", "y", "n", "true", "false", "1", "0"}
        if val_str not in valid_yes_no:
            return False, f"{key} must be Yes, No, or boolean"

    alcohol = str(form.get("alcohol", "")).strip().lower()
    # Accept flexible alcohol values: accepts "yes"/"no"/"maybe"/"sometimes"/"rarely" etc
    # Maps them appropriately for the ML model
    valid_alcohol = {"none", "no", "never", "occasionally", "sometimes", "frequently", "yes", "maybe", "rarely", "daily"}
    if alcohol and alcohol not in valid_alcohol:
        return False, "alcohol must be None, Occasionally, or Frequently"

    gender = str(form.get("gender", "")).strip().lower()
    if gender and gender not in {"male", "female", "m", "f", "1", "2"}:
        return False, "gender must be Male or Female"

    return True, ""


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint with MongoDB continuous monitoring status.
    
    Returns real-time MongoDB connectivity (from periodic background check)
    and last check timestamp for visibility into system health.
    """
    with _mongo_health_lock:
        mongo_connected = _mongo_health_status.get("connected", False)
        last_check_ts = _mongo_health_status.get("last_check", 0.0)
    
    # Calculate seconds since last check
    seconds_since_check = time.time() - last_check_ts if last_check_ts > 0 else None
    
    return jsonify({
        "status": "ok",
        "mongo_connected": mongo_connected,
        "mongo_db": MONGO_DB_NAME,
        "mongo_collection": MONGO_COLLECTION_NAME,
        "mongo_health_check_interval_seconds": MONGODB_HEALTH_CHECK_INTERVAL_SECONDS,
        "mongo_last_check_timestamp": last_check_ts,
        "mongo_seconds_since_last_check": seconds_since_check,
    })


@app.route("/chat", methods=["POST"])
@limiter.limit("20 per minute", key_func=_rate_limit_key)
def chat():
    started_at = time.perf_counter()
    data = request.get_json(silent=True) or {}
    user_message = _extract_chat_question(data)
    chat_history = _extract_chat_history(data)

    if not user_message:
        return jsonify({"reply": "No message provided"}), 400

    if chatbot_response is None:
        return jsonify({
            "reply": "Chat service is unavailable. Please check model dependencies and restart backend."
        }), 503

    try:
        result = chatbot_response(user_message, history=chat_history, return_meta=True)
        if isinstance(result, dict):
            latency_ms = round((time.perf_counter() - started_at) * 1000.0, 2)
            response_payload = {
                "reply": result.get("answer", ""),
                "confidence": result.get("confidence", "low"),
                "route": result.get("route", "unknown"),
                "best_distance": result.get("best_distance"),
                "gap": result.get("gap"),
                "context_count": result.get("context_count", 0),
                "timing_ms": result.get("timing_ms", {}),
                "ranking_meta": result.get("ranking_meta", {}),
                "latency_ms": latency_ms,
            }

            route = str(response_payload.get("route", "unknown"))
            monitor_entry = {
                "query": user_message,
                "route": route,
                "confidence": response_payload.get("confidence"),
                "best_distance": response_payload.get("best_distance"),
                "gap": response_payload.get("gap"),
                "context_count": response_payload.get("context_count"),
                "timing_ms": response_payload.get("timing_ms"),
                "ranking_meta": response_payload.get("ranking_meta"),
                "latency_ms": response_payload.get("latency_ms"),
                "fallback_triggered": route.startswith("fallback") or "fallback" in route,
            }
            chat_monitor_logger.info(json.dumps(monitor_entry, ensure_ascii=True))

            return jsonify(response_payload)

        latency_ms = round((time.perf_counter() - started_at) * 1000.0, 2)
        legacy_payload = {
            "reply": str(result),
            "confidence": "low",
            "route": "legacy",
            "latency_ms": latency_ms,
        }
        chat_monitor_logger.info(json.dumps({
            "query": user_message,
            "route": "legacy",
            "confidence": "low",
            "best_distance": None,
            "gap": None,
            "context_count": 0,
            "latency_ms": latency_ms,
            "fallback_triggered": False,
        }, ensure_ascii=True))
        return jsonify(legacy_payload)
    except Exception as e:
        return jsonify({"reply": f"Chat service error: {str(e)}"}), 500


@app.route("/translate", methods=["POST"])
@limiter.limit("120 per minute", key_func=_rate_limit_key)
def translate_api():
    """Translate dynamic content with cache, batching support, and safe fallback."""
    key_err = _require_api_key()
    if key_err:
        return key_err

    payload = request.get_json(silent=True) or {}
    target_lang = str(payload.get("lang", "en")).strip().lower()

    if not re.fullmatch(r"[a-z]{2,3}(-[A-Za-z]{2})?", target_lang):
        return jsonify({"error": "lang must be a valid language code"}), 400
    if GOOGLE_TRANSLATE_ALLOWED_LANGS and target_lang not in GOOGLE_TRANSLATE_ALLOWED_LANGS:
        return jsonify({"error": f"Unsupported lang '{target_lang}'"}), 400

    raw_texts = payload.get("texts")
    if raw_texts is None:
        raw_texts = [payload.get("text", "")]

    if not isinstance(raw_texts, list):
        return jsonify({"error": "texts must be a list of strings"}), 400
    if not raw_texts:
        return jsonify({"error": "texts is required"}), 400
    if len(raw_texts) > 100:
        return jsonify({"error": "texts max length is 100"}), 400

    texts = [str(item).strip() for item in raw_texts]
    if all(not t for t in texts):
        return jsonify({"error": "texts must include at least one non-empty string"}), 400

    translated_items = []
    any_fallback = False
    for text in texts:
        translated, source = _translate_dynamic_text(text, target_lang)
        is_fallback = source == "fallback"
        any_fallback = any_fallback or is_fallback
        translated_items.append(
            {
                "text": text,
                "translated": translated,
                "source": source,
                "fallback": is_fallback,
            }
        )

    # Backward-compatible single-item shape for existing clients.
    if len(translated_items) == 1 and "texts" not in payload:
        item = translated_items[0]
        return jsonify(
            {
                "translated": item["translated"],
                "lang": target_lang,
                "source": item["source"],
                "fallback": item["fallback"],
            }
        ), 200

    return jsonify(
        {
            "translations": translated_items,
            "lang": target_lang,
            "fallback": any_fallback,
        }
    ), 200


@app.route("/fallback-rate", methods=["GET"])
def fallback_rate():
    """Get current fallback rate statistics (production observability)."""
    try:
        from chatbot import get_fallback_rate
        if get_fallback_rate is None:
            return jsonify({"status": "unavailable"}), 503
        
        stats = get_fallback_rate()
        return jsonify(stats)
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/api/public/app-info", methods=["GET"])
def app_info():
    """Public endpoint providing application metadata (no authentication required)."""
    return jsonify({
        "app_name": "OssoPulse",
        "version": "1.0.0",
        "description": "AI-based osteoporosis risk screening tool",
        "disclaimer": "This app does not provide medical diagnosis. Results are educational risk estimates only.",
        "contact": "support@ossopulse.app",
        "privacy_url": "/privacy",
        "terms_url": "/terms"
    })


@app.route("/api/public/voice-script", methods=["GET"])
def voice_script():
    """Public endpoint providing approved landing narration text for TTS."""
    script = (
        "Hello and welcome to OssoPulse.\n\n"
        "This application helps you understand your osteoporosis risk level in a simple and clear manner.\n\n"
        "Please note carefully, this app does not diagnose osteoporosis and it does not replace consultation with a qualified medical professional. "
        "It only provides an AI-based risk assessment for awareness purposes.\n\n"
        "We collect basic information such as your age, gender, lifestyle habits, and certain medical history details. "
        "These inputs are used only to calculate your personalized risk score.\n\n"
        "Your data is kept secure and is not sold to any third party.\n\n"
        "Let me briefly explain how the app works.\n\n"
        "Step one: Create your account using your phone number.\n\n"
        "Step two: Enter your health and lifestyle details.\n\n"
        "Step three: Our machine learning model analyses your information.\n\n"
        "Step four: You receive your risk category — Low, Moderate, or High.\n\n"
        "Step five: You get personalized recommendations and reminder notifications to support your bone health.\n\n"
        "Osteoporosis affects over 200 million people worldwide. One in three women and one in five men above the age of fifty are at risk.\n\n"
        "It is always better to be aware early and take preventive steps.\n\n"
        "To continue, please select Sign Up if you are new, or Login if you already have an account.\n\n"
        "Thank you for choosing OssoPulse."
    )
    return jsonify({"script": script})


@app.route("/", methods=["GET"])
def index():
    """Lightweight landing endpoint so hitting '/' doesn't 404."""
    return jsonify({
        "status": "ok",
        "routes": [
            "/health",
            "/predict",
            "/predict_form",
            "/survey/questions",
            "/survey/submit",
            "/history",
            "/artifacts_check",
        ],
        "message": "Backend is running. Use POST /predict or /predict_form for inference, or GET /survey/questions to start a survey."
    })


@app.route("/predict", methods=["POST"])
@limiter.limit("5 per minute", key_func=_rate_limit_key)
def predict():
    key_err = _require_api_key()
    if key_err:
        return key_err
    user_id, user_err = _require_user_id()
    if user_err:
        return user_err
    try:
        model, feature_order = _load_artifacts()
    except Exception as exc:  # pragma: no cover - startup guard
        return jsonify({"error": str(exc)}), 503

    data = request.get_json(silent=True)
    if not data or "records" not in data:
        return jsonify({"error": "Request must be JSON with a 'records' list."}), 400

    records = data["records"]
    if not isinstance(records, list) or len(records) == 0:
        return jsonify({"error": "'records' must be a non-empty list."}), 400

    for rec in records:
        ok, msg = _validate_record(rec)
        if not ok:
            return jsonify({"error": f"Invalid input: {msg}"}), 400

    try:
        X = _prepare_frame(records, feature_order)
        input_dict = records
        input_vector = X.to_dict(orient="records")
        print("input_dict:", input_dict)
        print("input_vector:", input_vector)
        prob = model.predict_proba(X)[:, 1]
        pred = (prob >= data.get("threshold", 0.1)).astype(int)
    except Exception as exc:  # pragma: no cover - inference guard
        return jsonify({"error": f"Inference failed: {exc}"}), 400

    response_body = {
        "predictions": pred.tolist(),
        "probabilities": prob.tolist()
    }
    _save_prediction(user_id, "predict", {
        "predictions": response_body["predictions"],
        "probabilities": response_body["probabilities"],
        "inputs": records,
    })

    return jsonify(response_body)


@app.route("/predict_form", methods=["POST"])
@limiter.limit("5 per minute", key_func=_rate_limit_key)
def predict_form():
    key_err = _require_api_key()
    if key_err:
        return key_err
    user_id, user_err = _require_user_id()
    if user_err:
        return user_err
    try:
        model, feature_order = _load_artifacts()
    except Exception as exc:  # pragma: no cover - startup guard
        return jsonify({"error": str(exc)}), 503

    data = request.get_json(silent=True)
    if not data or "forms" not in data:
        return jsonify({"error": "Request must be JSON with a 'forms' list."}), 400

    forms = data["forms"]
    if not isinstance(forms, list) or len(forms) == 0:
        return jsonify({"error": "'forms' must be a non-empty list."}), 400

    for form in forms:
        ok, msg = _validate_form_input(form)
        if not ok:
            return jsonify({"error": f"Invalid input: {msg}"}), 400

    request_time_slot = str(data.get("time_slot", "")).strip().lower()
    if request_time_slot and request_time_slot not in {"morning", "afternoon", "evening"}:
        request_time_slot = ""

    shap_values_list = data.get("shap_values_list")
    if not isinstance(shap_values_list, list):
        shap_values_list = []

    try:
        X = _prepare_frame_from_forms(forms, feature_order)
        input_dict = forms
        input_vector = X.to_dict(orient="records")
        print("input_dict:", input_dict)
        print("input_vector:", input_vector)
        threshold_val = float(data.get("threshold", 0.1))
        prob = model.predict_proba(X)[:, 1]
        pred = (prob >= threshold_val).astype(int)
        risk_levels = [_risk_level(p) for p in prob]
        messages = [_risk_message(level) for level in risk_levels]
        generated = [
            _generate_tasks_bundle(
                f,
                user_id=str(user_id),
                risk_level=risk_levels[idx],
                shap_values=(
                    shap_values_list[idx]
                    if idx < len(shap_values_list) and isinstance(shap_values_list[idx], dict)
                    else None
                ),
                current_slot=request_time_slot or None,
                probability=float(prob[idx]),
            )
            for idx, f in enumerate(forms)
        ]
        tasks = [list(item.get("tasks", [])) for item in generated]
        matched_tags = [list(item.get("matched_tags", [])) for item in generated]
        top_factors = [list(item.get("top_factors", [])) for item in generated]
        top_factors_with_weight = [list(item.get("top_factors_with_weight", [])) for item in generated]
        factor_task_link = [dict(item.get("factor_task_link", {})) for item in generated]
        primary_action = [str(item.get("primary_action", "")) for item in generated]
        time_groups = [dict(item.get("time_groups", {})) for item in generated]
        type_groups = [dict(item.get("type_groups", {})) for item in generated]
        confidence = [float(item.get("confidence", 0.0)) for item in generated]
        confidence_label = [str(item.get("confidence_label", _get_confidence_label(confidence[idx]))) for idx, item in enumerate(generated)]
        confidence_band = [str(item.get("confidence_band", _get_confidence_band(confidence[idx]))) for idx, item in enumerate(generated)]
        confidence_reason = [str(item.get("confidence_reason", "")) for item in generated]
        confidence_note = [str(item.get("confidence_note", _get_confidence_note(risk_levels[idx], confidence[idx]))) for idx, item in enumerate(generated)]
        urgency = [_urgency_from_risk(level) for level in risk_levels]
        alerts = [_medical_alerts(f) for f in forms]
    except Exception as exc:  # pragma: no cover - inference guard
        return jsonify({"error": f"Inference failed: {exc}"}), 400

    response_body = {
        "predictions": pred.tolist(),
        "probabilities": prob.tolist(),
        "risk_levels": risk_levels,
        "urgency": urgency,
        "confidence": confidence,
        "confidence_label": confidence_label,
        "confidence_band": confidence_band,
        "confidence_reason": confidence_reason,
        "confidence_note": confidence_note,
        "messages": messages,
        "tasks": tasks,
        "matched_tags": matched_tags,
        "top_factors": top_factors,
        "top_factors_with_weight": top_factors_with_weight,
        "factor_task_link": factor_task_link,
        "primary_action": primary_action,
        "time_groups": time_groups,
        "type_groups": type_groups,
        "alerts": alerts,
    }

    _save_prediction(user_id, "predict_form", {
        "predictions": response_body["predictions"],
        "probabilities": response_body["probabilities"],
        "inputs": forms,
    })

    return jsonify(response_body)


# ============ DASHBOARD ENDPOINTS ============

@app.route("/api/user/dashboard", methods=["GET"])
@token_required
def api_dashboard():
    """
    Get dashboard data for logged-in user.
    Includes user info, latest risk assessment, recommendations preview, and reminder status.
    """
    try:
        user_id = request.current_user['user_id']
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # Get user info
        cursor.execute("SELECT full_name, phone_number, preferred_language FROM users WHERE id = ?", (user_id,))
        user_row = cursor.fetchone()
        if not user_row:
            return jsonify({"error": "User not found"}), 404
        
        full_name = user_row["full_name"]
        phone_number = user_row["phone_number"]
        preferred_language = user_row["preferred_language"] or "english"
        
        # Get latest risk assessment
        cursor.execute("""
            SELECT risk_score, risk_level, created_at, next_reassessment_date FROM risk_assessments
            WHERE user_id = ? ORDER BY created_at DESC LIMIT 1
        """, (user_id,))
        risk_row = cursor.fetchone()
        
        risk_data = None
        recommendations_preview = []
        
        if risk_row:
            risk_data = {
                "risk_score": risk_row["risk_score"],
                "risk_level": risk_row["risk_level"],
                "last_assessment_date": risk_row["created_at"],
                "next_reassessment_date": risk_row["next_reassessment_date"],
            }
            
            # Get recommendations preview (top 3)
            cursor.execute("""
                SELECT recommendation_text FROM recommendations
                WHERE user_id = ? ORDER BY created_at DESC LIMIT 3
            """, (user_id,))
            recommendations_preview = [
                row["recommendation_text"] for row in cursor.fetchall()
            ]
        
        conn.close()
        
        return jsonify({
            "full_name": full_name,
            "phone_number": phone_number,
            "preferred_language": preferred_language,
            "risk": risk_data,
            "recommendations_preview": recommendations_preview,
            "reminders_enabled": True,  # Default to enabled for new users
        })
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/user/recommendations", methods=["GET"])
@token_required
def api_get_recommendations():
    """
    Get full list of recommendations for user.
    """
    try:
        user_id = request.current_user['user_id']
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT recommendation_text, category FROM recommendations
            WHERE user_id = ? ORDER BY created_at DESC
        """, (user_id,))
        
        recommendations = [
            {
                "text": row["recommendation_text"],
                "category": row["category"],
            }
            for row in cursor.fetchall()
        ]
        
        conn.close()
        
        return jsonify({
            "recommendations": recommendations,
            "count": len(recommendations),
        })
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/user/tasks/upsert", methods=["POST"])
@token_required
def api_upsert_daily_task():
    """Upsert a Daily Plan task completion state for a specific user/date/task."""
    try:
        user_id = request.current_user['user_id']
        data = request.get_json() or {}

        task_name = str(data.get("task_name", "")).strip()
        task_date_raw = str(data.get("date", "")).strip()
        completed = bool(data.get("completed", False))

        if not task_name:
            return jsonify({"error": "task_name is required"}), 400
        if task_name not in DAILY_PLAN_TASKS:
            return jsonify({"error": "Unsupported task_name"}), 400

        task_date = _parse_iso_date(task_date_raw)
        if task_date is None:
            return jsonify({"error": "date must be YYYY-MM-DD"}), 400

        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute(
                """
                INSERT INTO daily_tasks (user_id, task_date, task_name, completed)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(user_id, task_date, task_name)
                DO UPDATE SET
                    completed = excluded.completed,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (user_id, task_date.isoformat(), task_name, 1 if completed else 0),
            )
            conn.commit()
        finally:
            conn.close()

        return jsonify({
            "status": "ok",
            "task": {
                "user_id": user_id,
                "date": task_date.isoformat(),
                "task_name": task_name,
                "completed": completed,
            },
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/user/tasks", methods=["GET"])
@token_required
def api_get_daily_tasks():
    """Fetch Daily Plan task records for a date range."""
    try:
        user_id = request.current_user['user_id']
        days_raw = request.args.get("days", "30")
        try:
            days = max(1, min(90, int(days_raw)))
        except Exception:
            days = 30

        end_date = datetime.utcnow().date()
        start_date = end_date - timedelta(days=days - 1)

        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        try:
            rows = conn.execute(
                """
                SELECT task_date, task_name, completed
                FROM daily_tasks
                WHERE user_id = ? AND task_date BETWEEN ? AND ?
                ORDER BY task_date ASC
                """,
                (user_id, start_date.isoformat(), end_date.isoformat()),
            ).fetchall()
        finally:
            conn.close()

        records = [
            {
                "date": row["task_date"],
                "task_name": row["task_name"],
                "completed": bool(row["completed"]),
            }
            for row in rows
        ]

        return jsonify({
            "records": records,
            "days": days,
            "required_tasks": DAILY_PLAN_TASKS,
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/user/tasks/insights", methods=["GET"])
@token_required
def api_get_daily_task_insights():
    """Return weekly completion and risk trend data for charts/feedback loop."""
    try:
        user_id = request.current_user['user_id']
        days_raw = request.args.get("days", "7")
        try:
            days = max(7, min(30, int(days_raw)))
        except Exception:
            days = 7

        end_date = datetime.utcnow().date()
        start_date = end_date - timedelta(days=days - 1)

        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        try:
            task_rows = conn.execute(
                """
                SELECT task_date, task_name, completed
                FROM daily_tasks
                WHERE user_id = ? AND task_date BETWEEN ? AND ?
                ORDER BY task_date ASC
                """,
                (user_id, start_date.isoformat(), end_date.isoformat()),
            ).fetchall()

            risk_rows = conn.execute(
                """
                SELECT risk_score, risk_level, created_at
                FROM risk_assessments
                WHERE user_id = ?
                ORDER BY created_at DESC
                LIMIT 8
                """,
                (user_id,),
            ).fetchall()
        finally:
            conn.close()

        tasks_by_date: dict[str, dict[str, bool]] = {}
        for row in task_rows:
            date_key = row["task_date"]
            if date_key not in tasks_by_date:
                tasks_by_date[date_key] = {task: False for task in DAILY_PLAN_TASKS}
            task_name = row["task_name"]
            if task_name in DAILY_PLAN_TASKS:
                tasks_by_date[date_key][task_name] = bool(row["completed"])

        completion_series = []
        total_slots = len(DAILY_PLAN_TASKS)
        for i in range(days):
            current = start_date + timedelta(days=i)
            key = current.isoformat()
            state = tasks_by_date.get(key, {task: False for task in DAILY_PLAN_TASKS})
            completed_count = sum(1 for task in DAILY_PLAN_TASKS if state.get(task) is True)
            completion_pct = (completed_count / total_slots) * 100 if total_slots else 0.0
            completion_series.append({
                "date": key,
                "completed_count": completed_count,
                "completion_pct": round(completion_pct, 1),
            })

        streak_days = 0
        for i in range(0, 365):
            current = end_date - timedelta(days=i)
            key = current.isoformat()
            state = tasks_by_date.get(key)
            if not state or not all(state.get(task) is True for task in DAILY_PLAN_TASKS):
                break
            streak_days += 1

        risk_trend = [
            {
                "risk_score": float(row["risk_score"]),
                "risk_level": row["risk_level"],
                "date": str(row["created_at"]).split(" ")[0],
            }
            for row in reversed(risk_rows)
        ]

        weekly_avg = (
            sum(item["completion_pct"] for item in completion_series) / len(completion_series)
            if completion_series
            else 0.0
        )

        return jsonify({
            "completion_series": completion_series,
            "weekly_completion_pct": round(weekly_avg, 1),
            "streak_days": streak_days,
            "risk_trend": risk_trend,
            "required_tasks": DAILY_PLAN_TASKS,
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/user/reminders", methods=["POST"])
@token_required
def api_toggle_reminders():
    """
    Enable or disable reminders for user.
    Request body: {"enabled": true/false}
    """
    try:
        user_id = request.current_user['user_id']
        data = request.get_json()
        enabled = data.get("enabled", True)
        
        # TODO: Store reminder preference in database
        # For now, just return success
        
        return jsonify({
            "reminders_enabled": enabled,
            "message": f"Reminders {('enabled' if enabled else 'disabled')}",
        })
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500



if __name__ == "__main__":
    _start_sync_backup_scheduler()
    
    # Initialize degraded mode queue for resilience
    _init_degraded_queue_db()
    
    # Start MongoDB health check before logging status
    _start_mongodb_health_check()
    
    # Do initial health check synchronously to seed the state
    if MONGO_URI:
        with _mongo_health_lock:
            initial_status = _mongo_health_check_once()
            _mongo_health_status["connected"] = initial_status
            _mongo_health_status["was_connected"] = initial_status
            _mongo_health_status["last_check"] = time.time()
    
    _log_mongo_startup_status()
    
    # Direct connection verification (gives clear ✅/❌ before Flask starts)
    _verify_mongodb_connection()
    
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)

import os
from dotenv import load_dotenv
import json
import joblib
import numpy as np
import pandas as pd
import sqlite3
from datetime import datetime, timedelta
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# Import authentication module
from auth import init_auth_db, signup_user, login_user, token_required, get_user_by_id

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
# Set default dev API key for easy development
API_KEY = os.environ.get("API_KEY", "dev-key")

app = Flask(__name__)
CORS(app)
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


def _generate_tasks(form_entry: dict) -> list[str]:
    tasks: list[str] = []
    bmi = _compute_bmi(form_entry)
    if bmi is not None and bmi < 18.5:
        tasks.append("Increase protein and calorie intake daily")

    alcohol = str(form_entry.get("alcohol", "")).lower()
    if alcohol in {"occasionally", "frequently"}:
        tasks.append("Limit alcohol intake to protect bone strength")

    smoking = str(form_entry.get("smoking", "")).lower()
    if smoking == "yes":
        tasks.append("Stop smoking to prevent further bone loss")

    if str(form_entry.get("activity_limited", "")).lower() == "yes" or str(form_entry.get("mobility_climb", "")).lower() == "yes":
        tasks.append("Perform 20–30 min weight-bearing exercise daily")

    return tasks


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
    
    data = request.get_json(silent=True)
    if not data or "survey_data" not in data:
        return jsonify({"error": "Request must include 'survey_data' field"}), 400
    
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
        tasks = _generate_tasks(survey_data)
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
        "recommended_tasks": tasks,
        "medical_alerts": alerts,
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
    return jsonify({"status": "ok"})


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
        tasks = [_generate_tasks(f) for f in forms]
        alerts = [_medical_alerts(f) for f in forms]
    except Exception as exc:  # pragma: no cover - inference guard
        return jsonify({"error": f"Inference failed: {exc}"}), 400

    response_body = {
        "predictions": pred.tolist(),
        "probabilities": prob.tolist(),
        "risk_levels": risk_levels,
        "messages": messages,
        "tasks": tasks,
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
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)

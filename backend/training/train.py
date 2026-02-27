import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import f1_score, precision_score, recall_score, roc_auc_score
from sklearn.model_selection import RandomizedSearchCV, train_test_split
from xgboost import XGBClassifier

# Paths
ROOT = Path(__file__).resolve().parent
BACKEND_ROOT = ROOT.parent
DATA_DIR = ROOT / "data"

# Model-B artifacts live under backend/artifacts to match the serving app
ARTIFACTS_DIR = BACKEND_ROOT / "artifacts"
ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

MODEL_PATH = ARTIFACTS_DIR / "calibrated_model.pkl"
FEATURES_PATH = ARTIFACTS_DIR / "feature_order.json"

# Files
FILES = {
    "demo": "DEMO_J.XPT",
    "femur": "DXXFEM_J.XPT",
    "bmi": "BMX_J.XPT",
    "mcq": "MCQ_J.XPT",
    "bio": "BIOPRO_J.XPT",  # contains LBXSCA (serum calcium)
}

RANDOM_STATE = 42
THRESHOLD = 0.10


def load_data():
    demo = pd.read_sas(DATA_DIR / FILES["demo"])
    femur = pd.read_sas(DATA_DIR / FILES["femur"])
    bmi = pd.read_sas(DATA_DIR / FILES["bmi"])
    mcq = pd.read_sas(DATA_DIR / FILES["mcq"])
    bio = pd.read_sas(DATA_DIR / FILES["bio"])  # LBXSCA present here

    df = demo.merge(femur, on="SEQN", how="inner")
    df = df.merge(bmi, on="SEQN", how="left")
    df = df.merge(mcq, on="SEQN", how="left")
    df = df.merge(bio, on="SEQN", how="left")
    return df


def build_features(df: pd.DataFrame):
    df = df.dropna(subset=["DXXNKBMD"]).copy()

    young_mean = 0.858
    young_sd = 0.120
    df["femur_tscore"] = (df["DXXNKBMD"] - young_mean) / young_sd
    df["osteoporosis"] = np.where(df["femur_tscore"] <= -2.5, 1, 0)

    basic_features = ["RIDAGEYR", "RIAGENDR", "BMXBMI"]
    basic_features = [f for f in basic_features if f in df.columns]
    if "RIDAGEYR" in df.columns:
        df["AGE_SQUARED"] = df["RIDAGEYR"] ** 2
        basic_features.append("AGE_SQUARED")

    mcq_cols = [c for c in df.columns if c.startswith("MCQ")]
    df_mcq = df[mcq_cols].replace({7: np.nan, 9: np.nan, 2: 0})

    # Calcium handling: LBXSCA is continuous; bin into 3 intake-like levels (Rarely/Sometimes/Daily)
    calcium_feature = pd.Series([np.nan] * len(df), index=df.index)
    if "LBXSCA" in df.columns:
        lbx = df["LBXSCA"]
        if lbx.notna().sum() > 0:
            try:
                calcium_feature = pd.qcut(
                    lbx, q=3, labels=[0, 1, 2], duplicates="drop"
                )
            except ValueError:
                calcium_feature = lbx.rank(method="average", pct=True).apply(
                    lambda p: 0 if p < 1 / 3 else (1 if p < 2 / 3 else 2)
                )
    calcium_feature = calcium_feature.astype(float).fillna(1).astype(int)

    X = pd.concat([df[basic_features], df_mcq, calcium_feature.rename("calcium_level")], axis=1)
    X = X.fillna(0)
    y = df["osteoporosis"]

    return X, y


def train_model(X: pd.DataFrame, y: pd.Series):
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=y
    )

    scale_pos_weight = (y_train == 0).sum() / (y_train == 1).sum()

    param_dist = {
        "n_estimators": [300, 400, 500, 600],
        "max_depth": [3, 4, 5],
        "learning_rate": [0.01, 0.03, 0.05],
        "subsample": [0.7, 0.8, 0.9],
        "colsample_bytree": [0.7, 0.8, 0.9],
    }

    # Model-B: tuned XGBoost classifier with calibration
    base_model = XGBClassifier(
        scale_pos_weight=scale_pos_weight,
        eval_metric="logloss",
        random_state=RANDOM_STATE,
    )

    search = RandomizedSearchCV(
        base_model,
        param_distributions=param_dist,
        n_iter=20,
        scoring="roc_auc",
        cv=5,
        verbose=1,
        n_jobs=-1,
        random_state=RANDOM_STATE,
    )
    search.fit(X_train, y_train)
    best_model = search.best_estimator_

    # Feature pruning
    importance = best_model.feature_importances_
    feat_df = (
        pd.DataFrame({"feature": X.columns, "importance": importance})
        .sort_values("importance", ascending=False)
    )
    important_features = feat_df[feat_df["importance"] > 0.005]["feature"]

    X_train_sel = X_train[important_features]
    X_test_sel = X_test[important_features]

    best_model.fit(X_train_sel, y_train)

    calibrated_model = CalibratedClassifierCV(best_model, method="isotonic", cv=3)
    calibrated_model.fit(X_train_sel, y_train)

    y_prob = calibrated_model.predict_proba(X_test_sel)[:, 1]
    y_pred = (y_prob >= THRESHOLD).astype(int)

    metrics = {
        "roc_auc": roc_auc_score(y_test, y_prob),
        "recall": recall_score(y_test, y_pred),
        "precision": precision_score(y_test, y_pred),
        "f1": f1_score(y_test, y_pred),
        "selected_features": list(important_features),
        "best_params": search.best_params_,
    }

    return calibrated_model, important_features, metrics


def save_artifacts(model, features):
    joblib.dump(model, MODEL_PATH)
    with open(FEATURES_PATH, "w", encoding="utf-8") as f:
        json.dump(list(features), f)


def main():
    df = load_data()
    X, y = build_features(df)
    model, features, metrics = train_model(X, y)
    save_artifacts(model, features)

    print("Training complete. Artifacts saved to", ARTIFACTS_DIR)
    print("Metrics:", json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()

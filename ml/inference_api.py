from __future__ import annotations

import argparse
from pathlib import Path

import joblib
import pandas as pd
from flask import Flask, jsonify, request

from preprocess import feature_columns


def create_app(model_path: Path) -> Flask:
    app = Flask(__name__)
    model = joblib.load(model_path)

    @app.post("/predict")
    def predict():
        payload = request.get_json(silent=True) or {}
        features = payload.get("features") or payload
        missing = [column for column in feature_columns() if column not in features]
        if missing:
            return jsonify({"error": f"Missing features: {missing}"}), 400

        frame = pd.DataFrame([{column: features[column] for column in feature_columns()}])
        probabilities = model.predict_proba(frame)[0]
        labels = list(model.classes_)
        best_index = int(probabilities.argmax())

        return jsonify(
            {
                "risk_level": labels[best_index],
                "risk_score": round(float(probabilities[best_index]), 3),
                "model_version": "random-forest-context-risk-v1",
                "reason": "structured context classification",
            }
        )

    return app


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("ml/model/shrimati_risk_model.pkl"),
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    app = create_app(args.model)
    app.run(host=args.host, port=args.port)


if __name__ == "__main__":
    main()

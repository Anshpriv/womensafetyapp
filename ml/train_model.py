from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline

from preprocess import VALID_LABELS, build_preprocessor, feature_columns, load_dataset


def train(dataset_path: Path, output_dir: Path, test_size: float, random_state: int) -> None:
    bundle = load_dataset(dataset_path)

    x_train, x_test, y_train, y_test = train_test_split(
        bundle.features,
        bundle.labels,
        test_size=test_size,
        random_state=random_state,
        stratify=bundle.labels,
    )

    pipeline = Pipeline(
        steps=[
            ("preprocess", build_preprocessor()),
            (
                "classifier",
                RandomForestClassifier(
                    n_estimators=200,
                    max_depth=8,
                    min_samples_leaf=2,
                    random_state=random_state,
                    class_weight="balanced",
                ),
            ),
        ]
    )

    pipeline.fit(x_train, y_train)
    predictions = pipeline.predict(x_test)

    labels = sorted(VALID_LABELS)
    report = classification_report(
        y_test,
        predictions,
        labels=labels,
        output_dict=True,
        zero_division=0,
    )
    matrix = confusion_matrix(y_test, predictions, labels=labels)

    output_dir.mkdir(parents=True, exist_ok=True)
    joblib.dump(pipeline, output_dir / "shrimati_risk_model.pkl")

    metadata = {
        "model_version": "random-forest-context-risk-v1",
        "model_type": "RandomForestClassifier",
        "feature_columns": feature_columns(),
        "labels": labels,
        "test_size": test_size,
        "random_state": random_state,
        "classification_report": report,
        "confusion_matrix": matrix.tolist(),
        "dataset_note": (
            "Prototype dataset only. Real-world deployment requires properly "
            "labelled and validated safety-event data."
        ),
    }
    (output_dir / "feature_schema.json").write_text(
        json.dumps(metadata, indent=2),
        encoding="utf-8",
    )

    print("Saved model:", output_dir / "shrimati_risk_model.pkl")
    print("Saved metadata:", output_dir / "feature_schema.json")
    print(classification_report(y_test, predictions, labels=labels, zero_division=0))
    print("Confusion matrix labels:", labels)
    print(matrix)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path("dataset/shrimati_safety_dataset.csv"),
    )
    parser.add_argument("--output-dir", type=Path, default=Path("ml/model"))
    parser.add_argument("--test-size", type=float, default=0.25)
    parser.add_argument("--random-state", type=int, default=42)
    args = parser.parse_args()

    train(args.dataset, args.output_dir, args.test_size, args.random_state)


if __name__ == "__main__":
    main()

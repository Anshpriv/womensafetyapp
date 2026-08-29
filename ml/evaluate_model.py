from __future__ import annotations

import argparse
from pathlib import Path

import joblib
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import train_test_split

from preprocess import VALID_LABELS, load_dataset


def evaluate(dataset_path: Path, model_path: Path, test_size: float, random_state: int) -> None:
    bundle = load_dataset(dataset_path)
    _, x_test, _, y_test = train_test_split(
        bundle.features,
        bundle.labels,
        test_size=test_size,
        random_state=random_state,
        stratify=bundle.labels,
    )

    model = joblib.load(model_path)
    predictions = model.predict(x_test)
    labels = sorted(VALID_LABELS)

    print(f"Accuracy: {accuracy_score(y_test, predictions):.3f}")
    print(classification_report(y_test, predictions, labels=labels, zero_division=0))
    print("Confusion matrix labels:", labels)
    print(confusion_matrix(y_test, predictions, labels=labels))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path("dataset/shrimati_safety_dataset.csv"),
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("ml/model/shrimati_risk_model.pkl"),
    )
    parser.add_argument("--test-size", type=float, default=0.25)
    parser.add_argument("--random-state", type=int, default=42)
    args = parser.parse_args()

    evaluate(args.dataset, args.model, args.test_size, args.random_state)


if __name__ == "__main__":
    main()

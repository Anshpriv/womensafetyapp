from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


LABEL_COLUMN = "label"

NUMERIC_FEATURES = [
    "shake_count",
    "shake_intensity",
    "shake_duration_ms",
    "movement_variance",
    "movement_frequency",
    "speed",
    "accuracy",
    "location_available",
    "geofence_violation",
    "distress_voice_detected",
    "recent_automatic_trigger_count",
    "recent_sos_count",
    "seconds_since_previous_trigger",
    "hour_of_day",
]

CATEGORICAL_FEATURES = ["trigger_type"]

VALID_LABELS = {"LOW_RISK", "SUSPICIOUS", "HIGH_RISK"}


@dataclass(frozen=True)
class DatasetBundle:
    features: pd.DataFrame
    labels: pd.Series


def load_dataset(path: str | Path) -> DatasetBundle:
    dataset_path = Path(path)
    data = pd.read_csv(dataset_path)
    validate_schema(data.columns)

    labels = data[LABEL_COLUMN].astype(str).str.upper()
    invalid_labels = sorted(set(labels) - VALID_LABELS)
    if invalid_labels:
        raise ValueError(f"Invalid labels found: {invalid_labels}")

    features = data[feature_columns()].copy()
    return DatasetBundle(features=features, labels=labels)


def validate_schema(columns: Iterable[str]) -> None:
    missing = set(required_columns()) - set(columns)
    if missing:
        raise ValueError(f"Dataset is missing columns: {sorted(missing)}")


def required_columns() -> list[str]:
    return feature_columns() + [LABEL_COLUMN]


def feature_columns() -> list[str]:
    return CATEGORICAL_FEATURES + NUMERIC_FEATURES


def build_preprocessor() -> ColumnTransformer:
    numeric_pipeline = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
        ]
    )

    categorical_pipeline = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("encoder", OneHotEncoder(handle_unknown="ignore")),
        ]
    )

    return ColumnTransformer(
        transformers=[
            ("numeric", numeric_pipeline, NUMERIC_FEATURES),
            ("categorical", categorical_pipeline, CATEGORICAL_FEATURES),
        ]
    )

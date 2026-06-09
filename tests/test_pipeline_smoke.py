"""
Cloud-free unit tests for the Iris pipeline — these run in the CI stage of
azure-pipelines.yml BEFORE any Azure resources are touched. They catch broken
data or broken training logic in seconds, on the build agent, for free.

Run locally with:  pytest tests -q
"""
import os

import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import train_test_split

# Repo root is the parent of this tests/ folder.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IRIS_CSV = os.path.join(ROOT, "data", "iris.csv")

EXPECTED_FEATURES = ["sepal_length", "sepal_width", "petal_length", "petal_width"]


def test_iris_csv_schema():
    """The data asset must have the 4 feature columns + the species label, 150 rows."""
    df = pd.read_csv(IRIS_CSV)
    assert len(df) == 150
    for col in EXPECTED_FEATURES + ["species"]:
        assert col in df.columns, f"missing column: {col}"
    assert set(df["species"].unique()) == {"setosa", "versicolor", "virginica"}


def test_no_missing_values():
    """Guard against a corrupted data asset sneaking into training."""
    df = pd.read_csv(IRIS_CSV)
    assert not df.isnull().values.any(), "iris.csv contains missing values"


def test_training_reaches_baseline_accuracy():
    """A smoke test of the exact estimator train.py uses — must clear a sane bar."""
    df = pd.read_csv(IRIS_CSV)
    y = df.pop("species")
    X = df[EXPECTED_FEATURES].values

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=42
    )
    clf = GradientBoostingClassifier(learning_rate=0.05)
    clf.fit(X_train, y_train)

    accuracy = clf.score(X_test, y_test)
    assert accuracy >= 0.80, f"accuracy {accuracy:.3f} below 0.80 baseline"

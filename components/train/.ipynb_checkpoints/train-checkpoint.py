import os
import argparse
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
import mlflow
import mlflow.sklearn

def main():
    # ── 1. Parse arguments ────────────────────────────────────────────────────
    parser = argparse.ArgumentParser()
    parser.add_argument("--train_data",            type=str,   help="path to train folder")
    parser.add_argument("--test_data",             type=str,   help="path to test folder")
    parser.add_argument("--learning_rate",         type=float, default=0.1)
    parser.add_argument("--registered_model_name", type=str,   help="name to register model as")
    parser.add_argument("--model",                 type=str,   help="output folder for model")
    args = parser.parse_args()

    # ── 2. MLflow autolog ─────────────────────────────────────────────────────
    # autolog() automatically logs: params, metrics, model artifact
    # No need to manually call mlflow.log_param() for sklearn params
    mlflow.sklearn.autolog()

    with mlflow.start_run():

        # ── 3. Load splits ────────────────────────────────────────────────────
        train_df = pd.read_csv(os.path.join(args.train_data, "data.csv"))
        test_df  = pd.read_csv(os.path.join(args.test_data,  "data.csv"))

        # Iris dataset: label column is "species", features are everything else
        label_col = "species"
        X_train = train_df.drop(columns=[label_col])
        y_train = train_df[label_col]
        X_test  = test_df.drop(columns=[label_col])
        y_test  = test_df[label_col]

        print(f"Training on {len(X_train)} rows, testing on {len(X_test)} rows")

        # ── 4. Train ──────────────────────────────────────────────────────────
        # C = 1/regularization_strength; we reuse learning_rate param as C
        # autolog logs: C, max_iter, solver, accuracy, etc. automatically
        model = LogisticRegression(C=args.learning_rate, max_iter=200)
        model.fit(X_train, y_train)

        # ── 5. Evaluate ───────────────────────────────────────────────────────
        y_pred   = model.predict(X_test)
        accuracy = accuracy_score(y_test, y_pred)
        print(f"Test Accuracy: {accuracy:.4f}")

        # mlflow.sklearn.autolog() already logged accuracy,
        # but we log it again explicitly so it's visible as a custom metric too
        mlflow.log_metric("test_accuracy", accuracy)

        # ── 6. Register model in AML Model Registry ───────────────────────────
        # mlflow.sklearn.log_model registers the model artifact in the run.
        # AML then picks it up and registers it in the workspace model registry.
        print(f"Registering model as: {args.registered_model_name}")
        mlflow.sklearn.log_model(
            sk_model=model,
            artifact_path="iris_model",
            registered_model_name=args.registered_model_name,
        )

        # ── 7. Save model to output path (for pipeline output wiring) ─────────
        os.makedirs(args.model, exist_ok=True)
        import pickle
        with open(os.path.join(args.model, "model.pkl"), "wb") as f:
            pickle.dump(model, f)

        print("Training complete.")

if __name__ == "__main__":
    main()

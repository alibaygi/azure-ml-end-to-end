import os
import argparse
import pandas as pd
from sklearn.model_selection import train_test_split
import mlflow

def main():
    # ── 1. Parse arguments injected by AML pipeline ──────────────────────────
    parser = argparse.ArgumentParser()
    parser.add_argument("--data",             type=str,   help="path to input CSV")
    parser.add_argument("--test_ratio",       type=float, default=0.2)
    parser.add_argument("--train_data",       type=str,   help="output folder for train split")
    parser.add_argument("--test_data",        type=str,   help="output folder for test split")
    args = parser.parse_args()

    # ── 2. MLflow: start a run and log parameters ─────────────────────────────
    # mlflow.start_run() is called automatically by AML when the job starts,
    # but we call it explicitly here so we can log params/metrics from this script.
    with mlflow.start_run():

        mlflow.log_param("test_ratio", args.test_ratio)

        # ── 3. Load data ──────────────────────────────────────────────────────
        df = pd.read_csv(args.data)
        print(f"Loaded {len(df)} rows, {df.shape[1]} columns")
        print(df.head())

        # ── 4. Log dataset stats to MLflow ────────────────────────────────────
        mlflow.log_metric("num_rows",     df.shape[0])
        mlflow.log_metric("num_features", df.shape[1] - 1)  # exclude label

        # ── 5. Split ──────────────────────────────────────────────────────────
        train_df, test_df = train_test_split(df, test_size=args.test_ratio, random_state=42)
        mlflow.log_metric("train_rows", len(train_df))
        mlflow.log_metric("test_rows",  len(test_df))

        # ── 6. Save outputs (AML mounts output paths as folders) ──────────────
        os.makedirs(args.train_data, exist_ok=True)
        os.makedirs(args.test_data,  exist_ok=True)
        train_df.to_csv(os.path.join(args.train_data, "data.csv"), index=False)
        test_df.to_csv( os.path.join(args.test_data,  "data.csv"), index=False)

        print("Data prep complete.")
        print(f"  Train: {len(train_df)} rows → {args.train_data}/data.csv")
        print(f"  Test : {len(test_df)}  rows → {args.test_data}/data.csv")

if __name__ == "__main__":
    main()

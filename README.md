# Azure ML + Azure DevOps: Iris MLOps Project

A minimal, well-commented project that teaches **two skills** with one tiny dataset:

1. **Azure ML** — author an end-to-end pipeline with the Python **SDK v2**
   (workspace → compute → environment → data → pipeline → model → live REST endpoint).
2. **Azure DevOps** — operationalize that *same* pipeline as a **CI/CD pipeline** with the
   **CLI v2** (lint/test/validate → train/register → deploy, gated by an approval).

The goal is not the model. It's understanding the **logic behind Azure ML and MLOps**:
what each primitive is, what it does, and why it exists.

> ### 👉 New here? Don't know where to start?
> Follow **[GETTING_STARTED.md](GETTING_STARTED.md)** — a click-by-click runbook.
> **Short version:** build the **Azure ML** workspace *first* (it's where models live), then wire
> up **Azure DevOps** (it's what ships them there). This project uses **Azure DevOps Pipelines**,
> **not** GitHub Actions — your code stays on GitHub and Azure DevOps just reads it.

## The two notebooks

| Notebook | Tool | You learn |
|----------|------|-----------|
| `aml_iris_end_to_end.ipynb` | **SDK v2** | How to *author & experiment* — run the lifecycle by hand |
| `aml_iris_devops.ipynb` | **CLI v2 + Azure DevOps** | How to *ship* — a `git push` runs CI → Train → Deploy |

Both notebooks reuse the **same** `components/`, `dependencies/conda.yml`, and `data/` —
only the orchestration layer changes (Python objects → declarative YAML).

> Reference (kept current): [What is Azure Machine Learning?](https://learn.microsoft.com/azure/machine-learning/overview-what-is-azure-machine-learning?view=azureml-api-2)
> · [Azure DevOps for CI/CD](https://learn.microsoft.com/azure/machine-learning/how-to-devops-machine-learning?view=azureml-api-2)

---

## What this covers

| Step | Concept | What you learn |
|------|---------|----------------|
| 1 | `MLClient` | How your notebook connects to AML |
| 2 | `AmlCompute` | What a compute cluster is and how scaling works |
| 3 | `Environment` | How AML packages your Python deps into Docker |
| 4 | `Data` asset | The difference between uploading data and registering it |
| 5 | `command()` vs `load_component()` | Two ways to define a pipeline step |
| 6 | `@dsl.pipeline` | How steps are chained and outputs wired |
| 7 | Job submission | What actually happens when you call `create_or_update` |
| 8 | MLflow tracking | What gets logged automatically vs manually |
| 9 | `ManagedOnlineEndpoint` | Endpoint vs deployment — why they're separate |
| 10 | Scoring | How to call the REST API |

---

## Folder structure

```
azue_ml_iris_project_devops/
├── aml_iris_end_to_end.ipynb       # NB1 — author with the SDK v2 (experiment)
├── aml_iris_devops.ipynb           # NB2 — operationalize with Azure DevOps (ship)
│
├── azure-pipelines.yml             # CI/CD pipeline: CI → Train → Deploy (3 stages, auto on push)
├── azure-infra-pipeline.yml        # IaC pipeline: provision workspace (manual-only, run once)
├── infra/
│   └── main.bicep                  #   Bicep template: workspace + storage + KV + compute
├── mlops/                          # CLI v2 declarative assets the CI/CD pipeline submits
│   ├── environment.yml             #   env  (reuses dependencies/conda.yml)
│   ├── data-asset.yml              #   data (reuses data/iris.csv)
│   ├── train-pipeline.yml          #   prep→train pipeline (YAML twin of NB1)
│   ├── endpoint.yml                #   managed online endpoint
│   └── deployment.yml              #   model → endpoint deployment
├── tests/
│   └── test_pipeline_smoke.py      # fast, cloud-free unit tests for the CI stage
│
├── dependencies/
│   └── conda.yml                   # Packages installed on the remote cluster (shared)
├── data/
│   └── iris.csv                    # The dataset (shared)
└── components/
    ├── data_prep/
    │   └── data_prep.py            # Step 1: split data, log stats to MLflow
    └── train/
        ├── train.py                # Step 2: train model, MLflow autolog
        └── train.yml               # Component definition (YAML format)
```

---

## Azure DevOps CI/CD (Notebook 2)

`azure-pipelines.yml` turns a `git push` into a deployed endpoint via three stages:

| Stage | Runs | Does |
|-------|------|------|
| **CI** | every PR & push | `flake8` + `pytest tests` + `az ml job validate` |
| **Train** | after CI passes | register env/data, run training pipeline, register model |
| **Deploy** | after approval | managed online endpoint + blue/green deploy + smoke test |

**One-time Azure DevOps setup** (click-by-click in [GETTING_STARTED.md](GETTING_STARTED.md)):
- A **GitHub service connection** — lets Azure DevOps read your repo + trigger on `git push`
  (auto-created when you make the pipeline). *Your code stays on GitHub.*
- An **Azure Resource Manager** service connection named `aml-arm-connection` — lets the pipeline
  talk to Azure ML. *(These two connections are different — see the runbook.)*
- A **variable group** `iris-mlops-vars` with `resourceGroup`, `workspace`, `location`
- An **environment** `iris-prod` with a manual **approval** check (the production gate)

> Uses **CLI v2** throughout (`az extension add -n ml`). Azure ML CLI v1 was retired 2025-09-30.

---

## Prerequisites

### Local machine
- Python 3.9+
- `az` CLI installed and logged in
- Azure subscription with an AML workspace

```bash
# Install Python SDK
pip install azure-ai-ml azure-identity

# Log in to Azure
az login

# Install AML CLI extension (for az ml commands)
az extension add -n ml
```

### Azure resources needed before running

**Option A — You already have a workspace:**
```bash
az account show --query id --output tsv          # get subscription_id
az group list --query "[].name" --output tsv      # get resource_group
az ml workspace list --output table               # get workspace name
```

**Option B — Create everything from scratch:**
```bash
az group create --name aml-rg --location germanywestcentral
az ml workspace create --name aml-ws --resource-group aml-rg --location germanywestcentral
```

---

## Running the notebook

1. Clone or unzip this project
2. Open `aml_iris_end_to_end.ipynb` in Jupyter
3. Edit the three values in **Step 1**:
   ```python
   subscription_id = "YOUR_SUBSCRIPTION_ID"
   resource_group  = "YOUR_RESOURCE_GROUP"
   workspace       = "YOUR_WORKSPACE_NAME"
   ```
4. Run cells **in order**, top to bottom
5. After Step 7 (pipeline submission), open the AML Studio link that gets printed
6. Delete the endpoint after Step 10 to avoid ongoing costs

> **Note:** The pipeline runs on a remote compute cluster — not your local machine.
> First run takes ~10 min because AML builds the Docker environment.
> Subsequent runs are faster (environment is cached).

---

## MLflow in this project

MLflow is embedded at every step. Here's exactly where and what it logs:

```
data_prep.py
  mlflow.log_param("test_ratio", ...)        → visible in Jobs > Metrics
  mlflow.log_metric("num_rows", ...)
  mlflow.log_metric("train_rows", ...)

train.py
  mlflow.sklearn.autolog()                   → logs ALL sklearn params automatically
  mlflow.log_metric("test_accuracy", ...)    → custom metric on top of autolog
  mlflow.sklearn.log_model(                  → saves model + registers in Model Registry
      registered_model_name="iris-..."
  )

endpoint deployment
  model loaded from MLflow artifact path    → no scoring script needed
```

You can see all logged metrics in **AML Studio → Experiments → iris-pipeline-experiment**.

---

## Key concepts clarified

**Datastore vs Storage Account**
A datastore is a *registration* inside AML that points to an existing storage account.
Running `ml_client.datastores.create_or_update()` does not create a container.
The container must exist first.

**Data Asset vs actual data**
A data asset stores a URI (an `azureml://` path) — not the data itself.
The data lives in blob storage. The asset is the bookmark.

**Component vs Job**
A component is a *definition* (what to run, what inputs/outputs).
A job is an *execution* of that definition with real values.

**Endpoint vs Deployment**
An endpoint is a URL + auth configuration.
A deployment is what attaches a model to that URL.
You can have multiple deployments under one endpoint (e.g. blue/green).

---

## Compute costs

| Resource | Cost when idle |
|----------|---------------|
| Compute cluster (`min_instances=0`) | Free — scales to zero |
| Managed online endpoint | **Billed per hour** — delete when done |
| Storage / data assets | Minimal (~cents/month for small datasets) |

Always run Step 11 (cleanup) when finished experimenting.

---

## Extending this project

- Add a **model quality gate** stage: fail the build if `test_accuracy` drops below a threshold
- Add a **second variable group + environment** for a full `dev → qa → prod` promotion chain
- Replace the manual approval with an **automated check** (e.g. an Azure Function gate)
- Schedule periodic **retraining** with an Event Grid or scheduled trigger
- Add a third pipeline step for batch scoring
- Replace LogisticRegression with a parameter sweep using `sweep()` job

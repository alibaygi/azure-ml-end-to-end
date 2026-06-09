# Getting Started — Click-by-Click Setup

This is the **runbook**. Follow it top to bottom, once. After this, every `git push`
to `main` runs your pipeline automatically.

> **Mental model in one line:** Azure ML is *where models live*; Azure DevOps is *what
> ships them there*. So you build the Azure ML workspace **first**, then point Azure DevOps at it.

---

## How the pieces connect

```
   GitHub repo                Azure DevOps                     Azure (your subscription)
   alibaygi/                  org: mlops-industrial            ┌──────────────────────────┐
   azure-ml-end-to-end                                         │  Resource group rg-aml-iris│
        │                     ┌─────────────────────┐          │  ┌──────────────────────┐ │
        │  (1) GitHub conn    │ Pipeline reads       │          │  │ Azure ML workspace   │ │
        ├────────────────────►│ azure-pipelines.yml  │          │  │ aml-iris-ws          │ │
        │   "read my code"    │                      │  (2) ARM │  │  • compute cluster   │ │
        │                     │  CI → Train → Deploy │──conn───►│  │  • model registry    │ │
        │  git push triggers  │                      │ "talk to │  │  • online endpoint   │ │
        └────────────────────►│                      │  Azure"  │  └──────────────────────┘ │
                              └─────────────────────┘          └──────────────────────────┘

   (1) GitHub service connection  = DevOps is allowed to READ your code + trigger on push
   (2) ARM service connection     = the pipeline is allowed to CREATE things in Azure ML
   These are TWO DIFFERENT connections. Don't mix them up.
```

There is **one** pipeline file: [`azure-pipelines.yml`](azure-pipelines.yml). The five files in
[`mlops/`](mlops/) are **assets** that pipeline submits — you never select them in any UI.

---

## PHASE 1 — Azure ML (do this first, from your laptop)

You need an Azure ML **workspace** before Azure DevOps has anything to deploy into.

```bash
# 1. Log in and pick your subscription
az login
az account set --subscription "<YOUR_SUBSCRIPTION_NAME_OR_ID>"

# 2. Install the ML CLI v2 extension (v1 was retired 2025-09-30)
az extension add -n ml

# 3. Create the resource group + workspace  (pick a region close to you)
az group create --name rg-aml-iris --location germanywestcentral
az ml workspace create --name aml-iris-ws --resource-group rg-aml-iris --location germanywestcentral
```

**Write down these three values — you'll paste them into Azure DevOps in Phase 2, Step 4:**

| Value | Example | Yours |
|---|---|---|
| `resourceGroup` | `rg-aml-iris` | |
| `workspace`     | `aml-iris-ws` | |
| `location`      | `germanywestcentral` | |

> You do **not** need to create the compute cluster or endpoint by hand — the pipeline does that.

---

## PHASE 1 ALTERNATIVE — Infrastructure as Code (IaC)

> **What is IaC?** Instead of running `az` commands by hand (Phase 1), you declare what
> resources you want in a file — and a pipeline creates them for you. Same result, but the
> definition lives in git: auditable, repeatable, shareable with a team.

This project uses **Bicep** for IaC. Bicep is Microsoft's native declarative language for
Azure resources. It's not YAML — it's a purpose-built language that compiles to ARM JSON —
but it plays the same role YAML plays in other IaC tools (Terraform HCL, Kubernetes YAML).
You define *what you want*; Azure figures out *how to create it*.

The key pattern for production MLOps is two separate pipelines:

```
azure-infra-pipeline.yml   trigger: none → manual only   provisions Azure resources
azure-pipelines.yml        trigger: main → on every push  trains + deploys models
```

The infra pipeline runs **once** (or whenever you need to rebuild the environment).
The CI/CD pipeline runs **every time code changes**. They share the same ARM service connection.

### Files added for IaC

| File | What it is |
|---|---|
| [`infra/main.bicep`](infra/main.bicep) | Declares all Azure resources: storage, key vault, app insights, AML workspace, compute cluster |
| [`azure-infra-pipeline.yml`](azure-infra-pipeline.yml) | Manual-only pipeline that deploys the Bicep template |

### Step 1 — Register the infra pipeline in Azure DevOps

Before running the infra pipeline, the `aml-arm-connection` service connection must exist
**and must be scoped to the subscription** (not a resource group, because it needs to *create*
the resource group). This is the only difference from Phase 2 Step 3:

- **Project settings → Service connections → New → Azure Resource Manager → Next**
- Identity type: keep the default
- Scope level: **Subscription** → pick your subscription → **leave Resource group blank**
- Name: `aml-arm-connection` → **Save**

> **Permissions note:** `infra/main.bicep` assigns RBAC roles (Key Vault Administrator +
> Storage Blob Data Contributor) to the workspace identity — the "credential-less" pattern,
> no keys stored anywhere. Creating role assignments requires the service connection's
> identity to have **Owner** or **User Access Administrator** on the subscription. If yours
> only has **Contributor**, run the pipeline with the parameter **`assignRbacRoles = false`**
> (the workspace still deploys; you grant those two roles by hand later).

Then register the pipeline:
- **Pipelines → New pipeline → GitHub → `alibaygi/azure-ml-end-to-end`**
- **Existing Azure Pipelines YAML file** → path: **`/azure-infra-pipeline.yml`** → **Continue → Save**

### Step 2 — Run it (the only manual click you ever need)

- **Pipelines → `azure-infra-pipeline` → Run pipeline**
- A form appears with the three parameters (pre-filled with defaults):

  | Parameter | Default |
  |---|---|
  | Resource group name | `rg-aml-iris` |
  | Azure ML workspace name | `aml-iris-ws` |
  | Azure region | `germanywestcentral` |

- Click **Run**. Azure reads [`infra/main.bicep`](infra/main.bicep) and creates everything.
- When it finishes (~5 min), the job log prints:
  ```
  ══════════════════════════════════════════════════════════
    Copy these into Pipelines → Library → iris-mlops-vars
  ══════════════════════════════════════════════════════════
    resourceGroup = rg-aml-iris
    workspace     = aml-iris-ws
    location      = germanywestcentral
  ══════════════════════════════════════════════════════════
  ```
- Copy those into the `iris-mlops-vars` variable group (Phase 2 Step 4). You're done.

> **Idempotent:** if you run the infra pipeline again on an existing workspace it does an
> update-or-skip — it will **not** delete and recreate resources or lose your models.

After this, continue from **Phase 2 Step 2** (create the main CI/CD pipeline).
The Step 3 service connection is already done above — skip it and go straight to Step 4.

---

## PHASE 2 — Azure DevOps (wire it up once)

Everything below happens at **https://dev.azure.com/mlops-industrial**.

### Step 1 — Create a project
- Top-right **+ New project**
- Name: `iris-mlops`  ·  Visibility: **Private**  ·  **Create**

### Step 2 — Connect the pipeline to your GitHub repo  *(this makes connection #1)*
- Left menu → **Pipelines** → **Create Pipeline**
- **Where is your code?** → choose **GitHub**
- Authorize Azure DevOps when GitHub asks (this creates the **GitHub service connection**)
- Select the repo **`alibaygi/azure-ml-end-to-end`**
- **Configure** → choose **Existing Azure Pipelines YAML file**
- Path: **`/azure-pipelines.yml`** → **Continue**
- On the review screen, click the **dropdown next to "Run"** → **Save** (just Save — **do NOT run yet**;
  Steps 3–5 must exist first or the run fails).

### Step 3 — Create the ARM service connection  *(this makes connection #2)*
This is the one named `aml-arm-connection` referenced in the YAML.
- **Project settings** (bottom-left gear) → **Service connections** → **New service connection**
- Choose **Azure Resource Manager** → **Next**
- Identity type: keep the **recommended default** (Workload identity federation / app registration — automatic)
- Scope level: **Subscription** → pick your subscription → Resource group: **`rg-aml-iris`**
- **Service connection name:** `aml-arm-connection`  ← must match the YAML exactly
- Check **Grant access permission to all pipelines** → **Save**

### Step 4 — Create the variable group  *(this is where your 3 values go)*
- **Pipelines** → **Library** → **+ Variable group**
- Name: `iris-mlops-vars`  ← must match the YAML exactly
- Add three variables (the values you wrote down in Phase 1):

  | Variable | Value |
  |---|---|
  | `resourceGroup` | `rg-aml-iris` |
  | `workspace` | `aml-iris-ws` |
  | `location` | `germanywestcentral` |

- **Save**

### Step 5 — Create the production gate (environment + approval)
- **Pipelines** → **Environments** → **New environment**
- Name: `iris-prod`  ← must match the YAML exactly  ·  Resource: **None** → **Create**
- Open `iris-prod` → top-right **⋮** → **Approvals and checks** → **+** → **Approvals**
- Add **yourself** as approver → **Create**

  > Now the **Deploy** stage pauses until you click **Approve** — your safety gate before
  > anything goes live and starts billing.

### Step 6 — Run it
- **Pipelines** → open **iris-mlops** → **Run pipeline** → **Run**
- First run asks you to **permit** the variable group + service connection — click **Permit**.
- Watch: **CI** → **Train** → (it pauses) → click **Approve** → **Deploy**.

Done. From now on, a `git push` to `main` runs the whole thing automatically.

---

## Troubleshooting

**"No hosted parallelism has been purchased or granted"** — brand-new free orgs can't run
Microsoft-hosted agents until Microsoft grants free parallelism. Fill in the 1-minute form at
https://aka.ms/azpipelines-parallelism-request (approval takes ~1–2 business days). This is the
single most common first-run blocker and is **not** a mistake in your setup.

**`az ml` not found in the pipeline** — the YAML installs it (`az extension add -n ml -y`); if a
step fails before that, check the ARM service connection name is exactly `aml-arm-connection`.

**Train stage fails on data/version** — re-runs reuse the same data asset version; the YAML
already tolerates this (`|| echo "...already exists"`), so this is informational, not fatal.

**Endpoint costs** — a managed online endpoint **bills per hour while it exists**. Delete it when
you're done experimenting:
```bash
az ml online-endpoint delete -n iris-endpoint-mlops --yes --no-wait
```

---

## What runs, in order

### Infrastructure pipeline (`azure-infra-pipeline.yml`) — run once, manually

| Stage | Trigger | Does |
|---|---|---|
| **Provision** | manual only (`trigger: none`) | creates resource group → deploys `infra/main.bicep` → workspace + compute cluster |

### CI/CD pipeline (`azure-pipelines.yml`) — runs on every push

| Stage | Trigger | Does | Gated? |
|---|---|---|---|
| **CI** | every push & PR to `main` | flake8 + pytest + `az ml job validate` | no |
| **Train** | after CI passes | register env+data, run training pipeline, register model | no |
| **Deploy** | after Train | create endpoint, blue/green deploy, smoke test, shift traffic | **yes — manual approval** |

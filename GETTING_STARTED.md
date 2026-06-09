# Getting Started — Click-by-Click Setup

This is the **runbook**. Follow the 7 steps **top to bottom, in order**. After this, every
`git push` to `main` runs your pipeline automatically.

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

**Two pipeline files** live in the repo, and they have different jobs:

| File | Trigger | Job |
|---|---|---|
| [`azure-infra-pipeline.yml`](azure-infra-pipeline.yml) | manual only | **provisions** the workspace + compute (run once, Step 3) |
| [`azure-pipelines.yml`](azure-pipelines.yml) | every `git push` | **trains + deploys** models (the CI/CD pipeline) |

The five files in [`mlops/`](mlops/) are **assets** the CI/CD pipeline submits — you never
select them in any UI.

---

## The order — do these 7 steps top to bottom

This project provisions the workspace with **Infrastructure as Code** (a Bicep template run by
the infra pipeline). The dependency chain forces this exact order:

| # | Step | Why it comes here |
|---|------|-------------------|
| 1 | Create the Azure DevOps project | the container for everything |
| 2 | Create the **ARM** service connection | the infra pipeline needs it to talk to Azure |
| 3 | **Run the infra pipeline** → workspace + compute | nothing can deploy into a workspace that doesn't exist |
| 4 | Create the variable group | uses the names the infra pipeline created |
| 5 | Register the **CI/CD** pipeline (GitHub conn) | needs the variable group + connection to validate |
| 6 | Create the production approval gate | the Deploy stage targets it |
| 7 | Run the CI/CD pipeline | everything it needs now exists |

> **Prefer to create the workspace by hand** instead of with the infra pipeline? Skip Step 3
> and do **[Alternative: provision from your laptop](#alternative--provision-the-workspace-from-your-laptop)**
> at the bottom, then come back and continue from Step 4.

Everything below happens at **https://dev.azure.com/mlops-industrial**.

---

## Step 1 — Create the Azure DevOps project
- Top-right **+ New project**
- Name: `iris-mlops`  ·  Visibility: **Private**  ·  **Create**

---

## Step 2 — Create the ARM service connection  *(connection #2 — auth to Azure)*

This is the one named `aml-arm-connection` referenced in **both** pipeline YAML files.

- **Project settings** (bottom-left gear) → **Service connections** → **New service connection**
- Choose **Azure Resource Manager** → **Next**
- Identity type: keep the **recommended default** (Workload identity federation)
- Scope level: **Subscription** → pick your subscription from the dropdown
- Resource group: leave as **All resource groups** — the infra pipeline needs subscription
  scope to create the resource group. *(You'll see an orange advisory — ignore it, not an error.)*
- **Service connection name:** type `aml-arm-connection`  ← **Save stays greyed out until you type this**
- Check **Grant access permission to all pipelines**
- Click **Save**

> **If Save appears to do nothing or silently fails**, your Entra ID tenant is blocking
> automatic app registration. Use the manual fallback:
> ```bash
> # 1. Get your subscription ID
> az account show --query id -o tsv
>
> # 2. Create the service principal (save the output — password shown only once)
> az ad sp create-for-rbac \
>   --name "aml-devops-sp" \
>   --role Contributor \
>   --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>
> ```
> Then back in Azure DevOps:
> - **New service connection → Azure Resource Manager → Next**
> - Change identity type to **"App registration or managed identity (manual)"**
> - Fill in: Subscription ID, Subscription name, Service principal ID (`appId`),
>   Service principal key (`password`), Tenant ID (`tenant`)
> - Service connection name: `aml-arm-connection` → **Verify** → **Save**

---

## Step 3 — Provision the workspace with the infra pipeline

This runs [`infra/main.bicep`](infra/main.bicep), which creates the storage account, key vault,
app insights, **the Azure ML workspace, and the compute cluster** — everything the CI/CD
pipeline needs to exist.

### 3a — Register the infra pipeline
- Left menu → **Pipelines** → **New pipeline** (or **Create Pipeline**)
- **Where is your code?** → **GitHub**
- *(First time only:)* a GitHub popup opens → **Authorize AzurePipelines** → when it asks which
  repos, choose **Only select repositories** → **`azure-ml-end-to-end`** → **Approve & Install**.
  *This is the moment GitHub connection #1 is created.*
- Select the repo **`alibaygi/azure-ml-end-to-end`**
- **Heads-up:** because the repo already contains `azure-pipelines.yml`, the wizard
  **auto-detects it and jumps straight to "Review your pipeline YAML"**, skipping the Configure
  step. That's fine — you'll just point it at the right file from here (see the box below).
- On the **Review** screen, **point it at the infra file**, then click the **▾ caret next to Run**
  → **Save**.

> #### 📌 The "pick the existing YAML file" trick (used in Step 3a **and** Step 5)
> The wizard lands you on **Review** already showing `azure-pipelines.yml`. To switch to a
> different existing file **without creating a new one**:
> 1. Next to the GitHub icon, **click the filename** in the breadcrumb
>    (`alibaygi/azure-ml-end-to-end / azure-pipelines.yml`).
> 2. A dropdown lists the YAML files already in your repo → **pick the one you want**.
> 3. **Watch the filename:**
>    - **No asterisk** = it loaded the *existing* file from the repo (✅ what you want).
>    - **`filename *`** (asterisk) = it thinks you're creating a *new* file. **Stop** — don't save,
>      or you'll commit the wrong content over a good file.
> 4. Save with the **▾ caret next to Run → Save**. With no asterisk, this just **registers the
>    pipeline — it does NOT commit anything to GitHub**.
> 5. **Do NOT** click a big **Save** button that pops up a *"Saving will commit … to the
>    repository"* dialog — that means you're on the new-file path. Close it and redo from step 1.

### 3b — Run it
- Open the pipeline you just saved → **Run pipeline**
- A parameter form appears. Set:

  | Field | Value |
  |---|---|
  | Resource group name | `rg-aml-iris` *(or your RG name)* |
  | Azure ML workspace name | `aml-iris-ws` |
  | Azure region | `germanywestcentral` |
  | ☐ Assign RBAC roles… | **leave unchecked** (default) — see note below |

  > **Assign RBAC roles?** This box is **unchecked by default**, which is the right choice for
  > the manual `az ad sp create-for-rbac --role Contributor` connection from Step 2 — a
  > Contributor principal **cannot** create role assignments, so checking it makes the deploy
  > fail with *"does not have permission to perform action
  > 'Microsoft.Authorization/roleAssignments/write'"*. Left unchecked, the workspace still
  > deploys and works fully (the key vault falls back to auto-managed access policies).
  > **Only check it** if your service connection has **Owner** or **User Access Administrator**
  > and you want the "credential-less" RBAC pattern.

- Click **Run** → **Permit** the service connection when asked.
- It runs **Validate** (lint + what-if preview) → **Provision** (~5 min). Wait for green checks.
- The job log ends by printing the three names to copy into Step 4:
  ```
  ══════════════════════════════════════════════════════════
    resourceGroup = rg-aml-iris
    workspace     = aml-iris-ws
    location      = germanywestcentral
  ══════════════════════════════════════════════════════════
  ```

> **Idempotent:** safe to re-run on an existing workspace — it updates or skips, never deletes.

---

## Step 4 — Create the variable group

- **Pipelines** → **Library** → **+ Variable group**
- Name: `iris-mlops-vars`  ← must match the YAML exactly
- Add three variables — **use the exact values the infra pipeline printed in Step 3**:

  | Variable | Value |
  |---|---|
  | `resourceGroup` | `rg-aml-iris` |
  | `workspace` | `aml-iris-ws` |
  | `location` | `germanywestcentral` |

- **Save**

> ⚠️ **The #1 silent failure:** these three values must **exactly match** what Step 3 created.
> A typo here means the CI/CD pipeline points at a workspace that doesn't exist.

---

## Step 5 — Register the CI/CD pipeline  *(the one that trains + deploys)*

Same flow as Step 3a, but this time you keep the **`azure-pipelines.yml`** file the wizard
already auto-detected. GitHub is already authorized from Step 3, so there's no popup this time.

- **Pipelines** → **New pipeline** → **GitHub** → **`alibaygi/azure-ml-end-to-end`**
- The wizard jumps straight to **Review**, already showing **`azure-pipelines.yml`** with
  **no asterisk** — that's exactly the file you want, so don't change anything.
  *(If it shows a different file, use the breadcrumb-dropdown trick in the Step 3a box to switch
  back to `azure-pipelines.yml`.)*
- Click the **▾ caret next to Run** → **Save** (**do NOT run yet** — Step 6 must exist first)

---

## Step 6 — Create the production approval gate
- **Pipelines** → **Environments** → **New environment**
- Name: `iris-prod`  ← must match the YAML exactly  ·  Resource: **None** → **Create**
- Open `iris-prod` → top-right **⋮** → **Approvals and checks** → **+** → **Approvals**
- Add **yourself** as approver → **Create**

  > Now the **Deploy** stage pauses until you click **Approve** — your safety gate before
  > anything goes live and starts billing.

---

## Step 7 — Run the CI/CD pipeline

> **Pre-flight check** — all of these must already exist (Steps 2–6):
> the workspace + compute (Step 3), `aml-arm-connection`, `iris-mlops-vars`, `iris-prod`.

- **Pipelines** → open the **`azure-ml-end-to-end`** pipeline → **Run pipeline**
- A **"Run pipeline"** panel slides in from the right (Pipeline version, Commit, Variables,
  Stages to run, Resources). **Leave everything at its defaults** — don't touch any of it.
- Click the blue **Run** button at the **bottom-right** of that panel.
- First run asks you to **Permit** the variable group + service connection — click **Permit**.
- Watch: **CI** → **Train** → (it pauses) → click **Approve** → **Deploy**.

Done. From now on, a `git push` to `main` runs the whole thing automatically.

---

## Alternative: provision the workspace from your laptop

Use this **instead of Step 3** if you'd rather create the workspace by hand than with the infra
pipeline. Run these from your terminal, then go back to Step 4.

```bash
# 1. Log in and pick your subscription
az login
az account set --subscription "<YOUR_SUBSCRIPTION_NAME_OR_ID>"

# 2. Install the ML CLI v2 extension (v1 was retired 2025-09-30)
az extension add -n ml

# 3. Create the resource group + workspace  (pick a region close to you)
az group create --name rg-aml-iris --location germanywestcentral
az ml workspace create --name aml-iris-ws --resource-group rg-aml-iris --location germanywestcentral

# 4. Create the compute cluster  (the CI/CD pipeline expects it to already exist —
#    it scales to 0 when idle, so it costs nothing between runs)
az ml compute create --name cpu-cluster --type amlcompute \
  --size Standard_E2ds_v4 --min-instances 0 --max-instances 2 \
  --resource-group rg-aml-iris --workspace-name aml-iris-ws
```

Then use these three values in Step 4: `resourceGroup=rg-aml-iris`, `workspace=aml-iris-ws`,
`location=germanywestcentral`.

---

## Troubleshooting

**"No hosted parallelism has been purchased or granted"** — brand-new free orgs can't run
Microsoft-hosted agents until Microsoft grants free parallelism. Fill in the 1-minute form at
https://aka.ms/azpipelines-parallelism-request (approval takes ~1–2 business days). This is the
single most common first-run blocker and is **not** a mistake in your setup.

**`az ml` not found in the pipeline** — the YAML installs it (`az extension add -n ml -y`); if a
step fails before that, check the ARM service connection name is exactly `aml-arm-connection`.

**Train stage: "compute 'cpu-cluster' not found"** — you haven't provisioned yet. Run Step 3
(or the laptop alternative) first; the compute cluster is owned by infra, not the CI/CD pipeline.

**Train stage fails on data/version** — re-runs reuse the same data asset version; the YAML
already tolerates this (`|| echo "...already exists"`), so this is informational, not fatal.

**Endpoint costs** — a managed online endpoint **bills per hour while it exists**. Delete it when
you're done experimenting:
```bash
az ml online-endpoint delete -n iris-endpoint-mlops --yes --no-wait
```

---

## What runs, in order

### Infrastructure pipeline (`azure-infra-pipeline.yml`) — run once, manually (Step 3)

| Stage | Trigger | Does |
|---|---|---|
| **Validate** | manual only (`trigger: none`) | bicep lint + what-if preview of changes |
| **Provision** | after Validate | creates resource group → deploys `infra/main.bicep` → workspace + compute cluster |

### CI/CD pipeline (`azure-pipelines.yml`) — runs on every push (Step 7)

| Stage | Trigger | Does | Gated? |
|---|---|---|---|
| **CI** | every push & PR to `main` | flake8 + pytest + `az ml job validate` | no |
| **Train** | after CI passes | register env+data, run training pipeline, register model | no |
| **Deploy** | after Train | create endpoint, blue/green deploy, smoke test, shift traffic | **yes — manual approval** |

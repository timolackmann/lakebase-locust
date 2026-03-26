# Locust load tester for Databricks Lakebase

[Locust](https://locust.io/) is a Python-based load testing tool that is easy to use and scale. You define a test plan and run it on one machine or distribute it for larger benchmarks.

Locust targets HTTP by default. This repository adds what you need to load-test [Databricks Lakebase](https://www.databricks.com/product/lakebase)—a cloud-native, fully managed PostgreSQL database service.

## Table of contents

- [What does this repository contain](#what-does-this-repository-contain)
- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
  - [Configuration](#configuration)
  - [Define your workloads](#define-your-workloads)
  - [Optional: Service principal setup](#optional-service-principal-setup)
  - [Running Locust](#running-locust)

## What does this repository contain

This repository includes:

- A custom Locust user class for testing **Databricks Lakebase** (see `[lakebase_user.py](lakebase_user.py)`).
- A sample scenario in `[locust.py](locust.py)`.
- Deployment helpers for **Kubernetes** and **Terraform** (AWS).
- Connection settings in `[config.json](config.json)` at the repo root.
- Quality-of-life scripts to provision a service principal and manage Databricks workspace IP access lists where relevant.

---

## Prerequisites

You need **Python** on the machine where Locust runs.

We recommend cloning this repository and using a virtual environment before installing dependencies from `[requirements.txt](requirements.txt)`:

```bash
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
```

This installs the Databricks SDK (for OAuth), helper scripts, and **Faker** for sample data generation.

---

## Getting started

Once the [prerequisites](#prerequisites) are met, follow the steps below.

### Configuration

Settings are read from `[config.json](config.json)` at the repository root, unless you set the `**CONFIG_PATH`** environment variable to another file.

Copy the example that matches your Lakebase deployment—**provisioned** or **autoscale**:

```bash
cp config.provisioned.example.json config.json   # or config.autoscale.example.json
```

Then edit `[config.json](config.json)` with your workspace and Lakebase details.

**Important:**

- The Lakebase user class supports **OAuth** only (see [Authenticate to a database instance](https://docs.databricks.com/aws/en/oltp/oauth) and [Create an OAuth role](https://docs.databricks.com/aws/en/oltp/projects/manage-roles#create-an-oauth-role)).
- The identity you use must have permission to connect to the Lakebase instance in your workspace.

**Required in `config.json`:**

- **workspace:** `host`, `client_id`, `client_secret`
- **provisioned:** `lakebase.mode: "provisioned"`, `lakebase.instance_names` (non-empty list), `lakebase.database`, `lakebase.user` (usually the same as `client_id`)
- **autoscale:** `lakebase.mode: "autoscale"`, `lakebase.project_id`, `lakebase.branch_id`, `lakebase.endpoint_id`, `lakebase.database`, `lakebase.user` (usually the same as `client_id`)

If you have not created a user or service principal yet, you can leave `client_id`, `client_secret`, and `lakebase.user` empty and follow [Optional: Service principal setup](#optional-service-principal-setup).

**Note:** Lakebase can expose read-only nodes. This project uses the **read/write** endpoint for all workloads.

---

### Define your workloads

`[locust.py](locust.py)` shows a sample workload built on the `LakebaseUser` class.

Besides **tasks** (the work Locust measures), you can run setup code before the load test—for example in `on_start`. That code runs for **each worker**, so avoid SQL that conflicts across workers. Prefer idempotent statements such as `CREATE TABLE IF NOT EXISTS` instead of bare `CREATE TABLE`.

Define tasks with the `@lakebase_task()` decorator on methods. Locust uses the method name in reports for response times. By default tasks are chosen with equal weight; use `@lakebase_task(weight=N)` to run some tasks more often than others.

Inside a task, run SQL with:

`self.run_sql(sql, params=None, commit=False)`

- `sql` — SQL string (use `%s` placeholders when passing `params`).
- `params` — optional sequence of values for parameterized queries.
- `commit` — set to `True` when the statement should be committed (for example inserts).

Example:

```python
from lakebase_user import LakebaseUser, lakebase_task

class MyUser(LakebaseUser):
    def on_start(self):
        super().on_start()
        self.run_sql("CREATE TABLE IF NOT EXISTS demo (id INT, name TEXT)")

    @lakebase_task()
    def insert(self):
        self.run_sql("INSERT INTO demo (id, name) VALUES (%s, %s)", [1, "alice"], commit=True)

    @lakebase_task(weight=2)
    def select(self):
        self.run_sql("SELECT * FROM demo LIMIT 10")
```

Here, `select` runs about twice as often as `insert`.

---

### Optional: Service principal setup

`[setup_service_principal.py](setup_service_principal.py)` creates a Databricks service principal, writes `client_id` and `client_secret` into your config, and grants it OAuth access to Lakebase.

**Required in config:** `workspace.host`, and a `lakebase` section with `mode` and—for autoscale—`project_id`, `branch_id`, `endpoint_id`, or—for provisioned—`instance_names`. Optional: `lakebase.database` (default `databricks_postgres`).

**Prerequisites:** [Databricks CLI](https://docs.databricks.com/dev-tools/cli/index.html) installed and authenticated (`databricks auth login`).

```bash
python setup_service_principal.py [--profile CLI-PROFILE] [--display-name NAME] [--config PATH]
```

If you choose to deploy via Terraform, you can also use the included terraform features and do not need to run the setup using this script.

---

### Running Locust

Run Locust locally from the repository root:

```bash
locust -f locust.py
```

Open [http://localhost:8089](http://localhost:8089), set the number of users and spawn rate, then start the test.

When you are ready to run distributed load tests, use:

- **[Kubernetes](k8s/README.md)** — build, push, and run Locust on a cluster.
- **Terraform (AWS)** — infrastructure under `[terraform/AWS/](terraform/AWS/)`; after apply, use `[terraform/AWS/run_locust.sh](terraform/AWS/run_locust.sh)` from that directory to sync config and drive masters/workers (see comments in the script for details).


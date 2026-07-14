# Locust load tester for Databricks Lakebase

[Locust](https://locust.io/) is a Python-based load testing tool that is easy to use and scale. You define a test plan and run it on one machine or distribute it for larger benchmarks.

Locust targets HTTP by default. This repository adds what you need to load-test [Databricks Lakebase](https://www.databricks.com/product/lakebase)—a cloud-native, fully managed PostgreSQL database service.

## Table of contents

- [What does this repository contain](#what-does-this-repository-contain)
- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
  - [Configuration](#configuration)
  - [Define your workloads](#define-your-workloads)
  - [Service principal setup (Kubernetes)](#service-principal-setup-kubernetes)
  - [Running Locust](#running-locust)

## What does this repository contain

This repository includes:

- A custom Locust user class for testing **Databricks Lakebase** (see `[lakebase_user.py](lakebase_user.py)`).
- A sample scenario in `[locust.py](locust.py)`.
- Deployment helpers for **Kubernetes** and **Terraform** (AWS).
- Connection settings in `[config.json](config.json)` at the repo root.
- **AWS (Terraform):** provisions EC2 Locust nodes, a Lakebase autoscale project, and a dedicated service principal with Lakebase access.
- **Kubernetes:** `[setup_service_principal.py](setup_service_principal.py)` to create a service principal and populate `config.json`.

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

Copy the example config and fill in your workspace and Lakebase details:

```bash
cp config.example.json config.json
```

Then edit `[config.json](config.json)`.

**Important:**

- The Lakebase user class supports **OAuth** only (see [Authenticate to a database instance](https://docs.databricks.com/aws/en/oltp/oauth) and [Create an OAuth role](https://docs.databricks.com/aws/en/oltp/projects/manage-roles#create-an-oauth-role)).
- The identity you use must have permission to connect to the Lakebase instance in your workspace.

**Required in `config.json`:**

- **workspace:** `host`, `client_id`, `client_secret`
- **lakebase:** `project_id`, `branch_id`, `endpoint_id`, `database`, `user` (usually the same as `client_id`)

On the **AWS Terraform path**, you only need to set `workspace.host` before the first apply. Terraform creates the service principal and Lakebase resources; `[terraform/AWS/run_locust.sh](terraform/AWS/run_locust.sh)` writes the remaining fields into `config.json` from Terraform outputs.

For **Kubernetes**, create the service principal with `[setup_service_principal.py](setup_service_principal.py)` (see [Service principal setup (Kubernetes)](#service-principal-setup-kubernetes)).

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

#### Distributed workers: primary keys and gevent

When you run Locust in **distributed mode** (master + workers), each worker process must generate **globally unique primary keys** for inserts. Locust assigns a stable 0-based ordinal per worker process: `self.environment.runner.worker_index` (see [Locust distributed docs](https://docs.locust.io/en/stable/running-distributed.html)).

The sample in [`locust.py`](locust.py) namespaces `INTEGER` primary keys by worker:

- **High bits:** `worker_index` (supports up to 2048 worker processes with signed `INTEGER`)
- **Low bits:** `random.getrandbits(20)` (unique across simulated users on the same worker)

For fleets larger than 2048 worker processes, use `BIGINT` primary keys or a composite key such as `(worker_index, seq)`.

**Gevent and heartbeats:** Locust workers use gevent greenlets. psycopg2/libpq performs blocking C I/O that gevent cannot patch, which stalls heartbeat messages and causes the master to drop workers under load. Any Locust file that uses psycopg2 must call `gevent.monkey.patch_all()` and `psycogreen.gevent.patch_psycopg()` **before** importing modules that use `psycopg2` (see the top of [`locust.py`](locust.py)). This is required for distributed runs; see [Testing other systems/protocols](https://docs.locust.io/en/stable/testing-other-systems.html).

---

### Service principal setup (Kubernetes)

For **Kubernetes** deployments, use `[setup_service_principal.py](setup_service_principal.py)` to create a dedicated Databricks service principal, write `client_id` and `client_secret` into `config.json`, and grant it OAuth access to Lakebase.

**Required in config:** `workspace.host`, and a `lakebase` section with `project_id`, `branch_id`, `endpoint_id`. Optional: `lakebase.database` (default `databricks_postgres`).

**Prerequisites:** [Databricks CLI](https://docs.databricks.com/dev-tools/cli/index.html) installed and authenticated (`databricks auth login`).

```bash
python setup_service_principal.py [--profile CLI-PROFILE] [--display-name NAME] [--config PATH]
```

The **AWS Terraform path** does not use this script. Terraform always creates a dedicated service principal, grants Lakebase access via `databricks_postgres_role`, and `run_locust.sh` populates `config.json` automatically.

---

### Running Locust

Run Locust locally from the repository root:

```bash
locust -f locust.py
```

Open [http://localhost:8089](http://localhost:8089), set the number of users and spawn rate, then start the test.

When you are ready to run distributed load tests, use:

- **[Kubernetes](k8s/README.md)** — build, push, and run Locust on a cluster. Provision a service principal with `setup_service_principal.py` before creating the `config.json` ConfigMap.
- **Terraform (AWS)** — infrastructure under `[terraform/AWS/](terraform/AWS/)`. `terraform apply` creates EC2 nodes, a Lakebase autoscale project, and a dedicated service principal. Then run `[terraform/AWS/run_locust.sh](terraform/AWS/run_locust.sh)` from that directory to write `config.json` from Terraform outputs and start the Locust fleet.


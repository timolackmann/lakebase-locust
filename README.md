# Locust Load Tester for Databricks Lakebase

Load test Databricks Lakebase (PostgreSQL) with [Locust](https://locust.io/). Uses a `LakebaseUser` base class and `@lakebase_task` decorator to define SQL workloads as Locust tasks with timing and request logging.

## Prerequisites

- Python 3 + venv (e.g. `python -m venv venv && source venv/bin/activate`)
- Dependencies: `locust`, `psycopg2-binary`, `databricks-sdk`, `faker` (see `requirements.txt` or install manually)

---

## Configuration

Config is read from **`config.json`** (or **`CONFIG_PATH`**). Use one of the example configs:

| Mode | When to use | Example |
|------|--------------|---------|
| **provisioned** | You have a provisioned Lakebase instance | `config.provisioned.example.json` |
| **autoscale** | You use Lakebase Autoscale | `config.autoscale.example.json` |

```bash
cp config.provisioned.example.json config.json   # or config.autoscale.example.json
# Edit config.json with your values
```

**Required in `config.json`:**

- **workspace:** `host`, `client_id` (if available, else see [Service principal setup](#sp-setup)), `client_secret` (if available, else see [Service principal setup](#sp-setup))
- **provisioned:** `lakebase.mode: "provisioned"`, `lakebase.instance_names` (non-empty list), `lakebase.database`, `lakebase.user` (usually same as `client_id`)
- **autoscale:** `lakebase.mode: "autoscale"`, `lakebase.project_id`, `lakebase.branch_id`, `lakebase.endpoint_id`, `lakebase.database`, `lakebase.user` (usually same as `client_id`)

`config.json` is typically gitignored; never commit real credentials.

---

##<a name="sp-setup"></a> Optional: Service principal setup

**`setup_service_principal.py`** creates a Databricks service principal, writes `client_id`/`client_secret` into config, and grants it OAuth access to Lakebase.

**Required in config:** `workspace.host`, `lakebase` section with `mode` and (for autoscale) `project_id`, `branch_id`, `endpoint_id`, or (for provisioned) `instance_names`. Optional: `lakebase.database` (default `databricks_postgres`).

**Prerequisites:** Databricks CLI installed and authenticated (`databricks auth login`).

```bash
python setup_service_principal.py [--profile PROFILE] [--display-name NAME] [--config PATH]
```

---

## Using `LakebaseUser` and `@lakebase_task`

1. **Subclass `LakebaseUser`** and call **`super().on_start()`** in `on_start` so the connection is created from config.
2. **Mark tasks with `@lakebase_task()`** or **`@lakebase_task(weight=N)`** instead of `@task`.
3. **Run SQL with `self.run_sql(sql)`**, `self.run_sql(sql, [params])`, or `self.run_sql(sql, params, commit=True)`.

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

---

## Running Locust

Ensure `config.json` (or `CONFIG_PATH`) is set. From the repo root:

```bash
locust -f locust.py
```

Open http://localhost:8089, set users and spawn rate, and start the test.

---

## Running on Kubernetes (GCP)

1. **Follow the instructions in the `k8s/` folder** (build and push image, create Artifact Registry repo, update image in manifests).
2. **Run the refresh script** from the repository root to (re)create ConfigMaps, master pod, service, and workers from the current `locust.py` and `config.json`:

```bash
./refresh-deployment.sh
```

Requires `kubectl` configured for your cluster. For the Locust web UI, port-forward: `kubectl port-forward service/master 8089:8089` then open http://localhost:8089.


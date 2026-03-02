# Locust Load Tester for Databricks Lakebase

Load test Databricks Lakebase (PostgreSQL) using [Locust](https://locust.io/). This project provides a `LakebaseUser` base class and `@lakebase_task` decorator so you can define SQL workloads and run them as Locust tasks with timing and request logging.

## Prerequisites

- Python 3 with a virtual environment (e.g. `python -m venv venv && source venv/bin/activate`)
- Dependencies: `locust`, `psycopg2-binary`, `databricks-sdk`, `faker` (see your project’s requirements or install manually)

## Config file: which one to use

Config is read from **`config.json`** by default, or from the path in the **`CONFIG_PATH`** environment variable.

There are two modes, each with its own example config:

| Mode           | When to use it                         | Example config                     |
|----------------|----------------------------------------|------------------------------------|
| **provisioned** | You have a provisioned Lakebase instance (instance name(s)) | `config.provisioned.example.json` |
| **autoscale**   | You use Lakebase Autoscale (project/branch/endpoint)        | `config.autoscale.example.json`   |

### 1. Provisioned Lakebase

- Copy the provisioned example and fill in your values:

  ```bash
  cp config.provisioned.example.json config.json
  ```

- Edit `config.json`:
  - **workspace**: `host`, `client_id`, `client_secret` (Databricks workspace OAuth app)
  - **lakebase**: `mode: "provisioned"`, `instance_names` (list of instance names), `schema`, `user`

- Required: `lakebase.instance_names` must be a non-empty list. The code uses the first instance and `workspace.database` APIs to get connection details and credentials.

### 2. Lakebase Autoscale

- Copy the autoscale example and fill in your values:

  ```bash
  cp config.autoscale.example.json config.json
  ```

- Edit `config.json`:
  - **workspace**: same as above
  - **lakebase**: `mode: "autoscale"`, `project_id`, `branch_id`, `endpoint_id`, `schema`, `user`

- Required: `project_id`, `branch_id`, and `endpoint_id`. The code uses `workspace.postgres` APIs to resolve the endpoint and generate credentials.

### Using a different config path

Set `CONFIG_PATH` to the path of your config file:

```bash
export CONFIG_PATH=/path/to/my_config.json
locust -f locust.py --host=localhost
```

**Note:** `config.json` is typically gitignored because it contains secrets. Use the example configs as templates and never commit real credentials.

---

## Using `lakebase_task` in your Locust file

Your load-test behaviour lives in a user class that subclasses **`LakebaseUser`** and uses **`@lakebase_task`** for each task.

### 1. Subclass `LakebaseUser`

Use `LakebaseUser` instead of `HttpUser` so each simulated user gets its own Lakebase connection and `run_sql()`:

```python
from lakebase_user import LakebaseUser, lakebase_task

class MyUser(LakebaseUser):
    ...
```

### 2. Call `super().on_start()` to connect

In `on_start`, call the base implementation so the connection is created from your config (provisioned or autoscale):

```python
def on_start(self):
    super().on_start()  # establishes self.conn from config
    # optional: create tables, prepare state, etc.
```

### 3. Mark tasks with `@lakebase_task`

Use **`@lakebase_task()`** (or **`@lakebase_task(weight=N)`**) instead of Locust’s `@task` so that:

- The method is registered as a Locust task
- Response time and success/failure are reported to Locust

```python
@lakebase_task()
def insert_record(self):
    self.run_sql("INSERT INTO ... VALUES (%s, %s)", [a, b], commit=True)

@lakebase_task(weight=2)  # this task runs twice as often as weight=1
def read_record(self):
    self.run_sql("SELECT ...")
```

- **No arguments**: `@lakebase_task()` — same as weight 1.
- **Weight**: `@lakebase_task(weight=N)` — relative probability of picking this task.

### 4. Run SQL inside tasks with `run_sql`

Inside a `@lakebase_task` method, use **`self.run_sql()`** for all database work:

- `self.run_sql(sql)` — no parameters
- `self.run_sql(sql, [a, b])` or `self.run_sql(sql, (a, b))` — parameterized query
- `self.run_sql(sql, params, commit=True)` — execute and commit

Use parameterized queries to avoid SQL injection. Each call uses a dedicated cursor on that user’s connection; connections are not shared between users or workers.

### Minimal example

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

- **Config:** Ensure `config.json` (or `CONFIG_PATH`) is set for the mode you use (provisioned or autoscale).
- **User class:** Point Locust at your file and user class (default class name is often inferred; specify with `-u` if needed).

Example:

```bash
locust -f locust.py
```

Then open the web UI (default http://localhost:8089), set number of users and spawn rate, and start the test. Tasks decorated with `@lakebase_task` will appear in Locust’s stats with response times and success/failure.

---

## Summary

| What you need | What to do |
|---------------|------------|
| **Right config** | Use `config.provisioned.example.json` or `config.autoscale.example.json` as template → save as `config.json` (or set `CONFIG_PATH`). Set `lakebase.mode` and the required fields for that mode. |
| **Lakebase tasks in `locust.py`** | Subclass `LakebaseUser`, call `super().on_start()` in `on_start`, use `@lakebase_task()` or `@lakebase_task(weight=N)` on task methods, and run all SQL via `self.run_sql(...)`. |

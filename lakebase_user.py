"""
Locust helper for Databricks Lakebase (PostgreSQL).
- @lakebase_task: drop-in replacement for @task with timing and request logging.
- LakebaseUser: connection setup and run_sql() for all cursor/execute logic.

Each simulated user gets its own LakebaseUser instance and its own DB connection
(created in on_start). run_sql() uses a fresh cursor per call on that user's
connection only—no connection or cursor sharing between users or workers, so
multi-worker and high user counts correctly simulate many independent users.

Config from config.json (or CONFIG_PATH). Set lakebase.mode to "provisioned" (default)
or "autoscale". Provisioned uses instance_names and workspace.database APIs; autoscale
uses project_id, branch_id, endpoint_id and workspace.postgres APIs.
"""

import json
import os
import time
import uuid
import psycopg2
from databricks.sdk import WorkspaceClient
from locust import User, task

DEFAULT_DATABASE = "databricks_postgres"


def load_config():
    """Load config from CONFIG_PATH, or config.json, or config.example.json."""
    path = os.environ.get("CONFIG_PATH", "config.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def lakebase_task(weight=1, batch_size=1):
    """Decorator that registers a method as a Locust task with timing and request event logging."""
    def middle(func):
        @task(weight=weight)
        def run_task(self):
            name = func.__name__
            exception = None
            start_time = time.perf_counter()
            try:
                func(self)
            except (Exception, psycopg2.DatabaseError) as error:
                exception = error
            finally:
                response_time_ms = int((time.perf_counter() - start_time) * 1000)
                self.environment.events.request.fire(
                    request_type="postgres_failure" if exception else "postgres_success",
                    name=name,
                    response_time=response_time_ms,
                    response_length=0,
                    exception=exception,
                )
        return run_task
    return middle

class LakebaseUser(User):
    """
    Base user class that establishes a connection to Databricks Lakebase.
    Use the @lakebase_task decorator on task methods for timing and request logging.

    One instance per simulated user; each instance has its own connection (self.conn)
    and run_sql() uses a new cursor per call on that connection only—safe for
    multi-worker and many users.
    """

    abstract = True

    def __init__(self, environment):
        super().__init__(environment)
        self.conn = None  # per-user connection; never shared
        self._workspace = None
        self._instance_name = None
        self._config = None

    def on_start(self):
        """Establish connection to Lakebase using config; dispatches on lakebase.mode (provisioned vs autoscale)."""
        self._config = load_config()
        ws = self._config["workspace"]
        self._workspace = WorkspaceClient(
            host=ws["host"],
            client_id=ws["client_id"],
            client_secret=ws["client_secret"],
        )
        lakebase = self._config["lakebase"]
        mode = lakebase.get("mode", "provisioned")
        if mode == "provisioned":
            self._connect_provisioned(lakebase)
        elif mode == "autoscale":
            self._connect_autoscale(lakebase)
        else:
            raise ValueError(f"lakebase.mode must be 'provisioned' or 'autoscale', got: {mode!r}")

    def _connect_provisioned(self, lakebase: dict):
        """Connect using provisioned database: instance_names and workspace.database APIs."""
        instance_names = lakebase.get("instance_names") or []
        if not instance_names:
            raise ValueError("lakebase.instance_names must be a non-empty list for mode=provisioned")
        database = lakebase.get("database") or DEFAULT_DATABASE
        instance = self._workspace.database.get_database_instance(name=instance_names[0])
        cred = self._workspace.database.generate_database_credential(
            request_id=str(uuid.uuid4()),
            instance_names=instance_names,
        )
        self.conn = psycopg2.connect(
            host=instance.read_write_dns,
            dbname=database,
            user=lakebase["user"],
            password=cred.token,
            sslmode="require",
        )

    def _connect_autoscale(self, lakebase: dict):
        """Connect using Lakebase Autoscale: project_id, branch_id, endpoint_id and workspace.postgres APIs."""
        project_id = lakebase.get("project_id")
        branch_id = lakebase.get("branch_id")
        endpoint_id = lakebase.get("endpoint_id")
        if not project_id or not branch_id or not endpoint_id:
            raise ValueError(
                "lakebase.project_id, lakebase.branch_id and lakebase.endpoint_id are required for mode=autoscale"
            )
        endpoint_name = f"projects/{project_id}/branches/{branch_id}/endpoints/{endpoint_id}"
        print(f"Connecting to endpoint: {endpoint_name}")
        endpoint = self._workspace.postgres.get_endpoint(name=endpoint_name)
        host = None
        if endpoint.status and endpoint.status.hosts:
            host = endpoint.status.hosts.host
        if not host:
            raise ValueError(f"Endpoint {endpoint_name} has no host; endpoint may not be ready")
        cred = self._workspace.postgres.generate_database_credential(endpoint=endpoint_name)
        database = lakebase.get("database") or DEFAULT_DATABASE
        self.conn = psycopg2.connect(
            host=host,
            dbname=database,
            user=lakebase["user"],
            password=cred.token,
            sslmode="require",
        )

    def run_sql(self, sql, params=None, commit=False):
        """
        Execute a SQL statement on this user's connection. Use from within a @lakebase_task method.
        Creates a new cursor for this call only (no shared cursor state); safe for concurrent users.
        On failure, rolls back the connection so it is usable for the next task.
        """
        if not self.conn:
            return
        try:
            with self.conn.cursor() as cur:
                if params is not None:
                    cur.execute(sql, params)
                else:
                    cur.execute(sql)
            if commit:
                self.conn.commit()
        except Exception:
            if self.conn:
                self.conn.rollback()
            raise

    def on_stop(self):
        """Close the database connection when the user stops."""
        if self.conn:
            try:
                self.conn.close()
            except Exception:
                pass
            self.conn = None

"""
Helper class for Locust load tests against Databricks Lakebase (PostgreSQL).
Handles connection setup and timed operation execution with request logging.
"""

import time
import uuid
import psycopg2
from databricks.sdk import WorkspaceClient
from locust import User


class LakebaseUser(User):
    """
    Base user class that establishes a connection to Databricks Lakebase
    and provides execute_timed() for running operations with response-time logging.
    """

    abstract = True

    def __init__(self, environment):
        super().__init__(environment)
        self.conn = None
        self._workspace = None
        self._instance_name = None

    def on_start(self):
        """Establish connection to Lakebase using Databricks workspace credentials."""
        self._instance_name = getattr(self, "lakebase_instance_name", "timo-lackmann-demo")
        self._workspace = WorkspaceClient()
        instance = self._workspace.database.get_database_instance(name=self._instance_name)
        cred = self._workspace.database.generate_database_credential(
            request_id=str(uuid.uuid4()),
            instance_names=[self._instance_name],
        )
        self.conn = psycopg2.connect(
            host=instance.read_write_dns,
            dbname="databricks_postgres",
            user=getattr(self, "lakebase_user", "timo.lackmann@databricks.com"),
            password=cred.token,
            sslmode="require",
        )

    def execute_timed(self, name, operation, commit=False):
        """
        Run an operation, measure elapsed time, and fire a Locust request event.

        :param name: Request name for Locust statistics (e.g. "create_table", "insert_record").
        :param operation: Callable that takes no arguments. Use self.conn (or self.conn.cursor())
                         inside it to run SQL. Must not capture exceptions; they are handled here.
        :param commit: If True, call conn.commit() after a successful operation.
        """
        start_time = time.perf_counter()
        exception = None
        try:
            operation()
            if commit and self.conn:
                self.conn.commit()
        except (Exception, psycopg2.DatabaseError) as error:
            exception = error
            if self.environment:
                print(error)
        finally:
            response_time_ms = int((time.perf_counter() - start_time) * 1000)
            if self.environment and hasattr(self.environment, "events"):
                self.environment.events.request.fire(
                    request_type="postgres_failure" if exception else "postgres_success",
                    name=name,
                    response_time=response_time_ms,
                    response_length=0,
                    exception=exception,
                )

    def on_stop(self):
        """Close the database connection when the user stops."""
        if self.conn:
            try:
                self.conn.close()
            except Exception:
                pass
            self.conn = None

"""
Lakebase server-side metrics collector for Locust load tests.

Periodically samples Postgres system views and feeds them into Locust's request
event stream so they appear in the Locust web UI and CSV reports alongside
client-side latencies.

Collected metrics:
  - pg_stat_activity:    connection counts by state (active, idle, total)
  - pg_stat_database:    transaction throughput, tuple throughput, cache hit ratio,
                         deadlocks, conflicts, temp bytes
  - pg_locks:            granted vs waiting lock counts
  - pg_stat_user_tables: seq scans, index scans, live/dead tuples per table
  - pg_stat_statements:  per-query call deltas and mean execution time (requires extension)

Usage — add one import to your locustfile (after the gevent/psycogreen setup):

    import lakebase_metrics  # noqa: F401

The collector starts automatically when Locust begins a test and stops when it ends.
It runs only on the master (or standalone); workers are unaffected.

The sampling interval defaults to 5 seconds. Override with:

    LAKEBASE_METRICS_INTERVAL=10 locust -f locust.py

The collector opens a dedicated monitoring connection using the same config.json as
LakebaseUser. If pg_stat_statements is not already enabled, the collector will attempt
CREATE EXTENSION IF NOT EXISTS pg_stat_statements; if that fails it gracefully skips
per-query metrics.
"""

import json
import os
import time
import uuid
import threading

import psycopg2
from databricks.sdk import WorkspaceClient
from locust import events

DEFAULT_DATABASE = "databricks_postgres"
METRICS_INTERVAL = int(os.environ.get("LAKEBASE_METRICS_INTERVAL", "5"))


def _load_config():
    path = os.environ.get("CONFIG_PATH", "config.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _connect(config):
    """Open a monitoring connection to Lakebase using the same config as LakebaseUser."""
    ws_cfg = config["workspace"]
    ws = WorkspaceClient(
        host=ws_cfg["host"],
        client_id=ws_cfg["client_id"],
        client_secret=ws_cfg["client_secret"],
    )
    lakebase = config["lakebase"]
    mode = lakebase.get("mode", "provisioned")
    database = lakebase.get("database") or DEFAULT_DATABASE
    user = lakebase["user"]

    if mode == "provisioned":
        instance_names = lakebase.get("instance_names") or []
        instance = ws.database.get_database_instance(name=instance_names[0])
        cred = ws.database.generate_database_credential(
            request_id=str(uuid.uuid4()),
            instance_names=instance_names,
        )
        return psycopg2.connect(
            host=instance.read_write_dns,
            dbname=database,
            user=user,
            password=cred.token,
            sslmode="require",
        )
    else:
        project_id = lakebase["project_id"]
        branch_id = lakebase["branch_id"]
        endpoint_id = lakebase["endpoint_id"]
        endpoint_name = f"projects/{project_id}/branches/{branch_id}/endpoints/{endpoint_id}"
        endpoint = ws.postgres.get_endpoint(name=endpoint_name)
        host = endpoint.status.hosts.host
        cred = ws.postgres.generate_database_credential(endpoint=endpoint_name)
        return psycopg2.connect(
            host=host,
            dbname=database,
            user=user,
            password=cred.token,
            sslmode="require",
        )


class LakebaseMetricsCollector:
    """Samples Lakebase server-side metrics and fires them as Locust request events."""

    def __init__(self):
        self._conn = None
        self._config = None
        self._has_pg_stat_statements = False
        self._stop = threading.Event()
        self._thread = None
        self._prev_db_stats = None
        self._prev_stmt_stats = {}

    def start(self, config):
        self._config = config
        try:
            self._conn = _connect(config)
            self._conn.autocommit = True
        except Exception as e:
            print(f"[lakebase_metrics] Could not connect for monitoring: {e}")
            return

        try:
            with self._conn.cursor() as cur:
                cur.execute("CREATE EXTENSION IF NOT EXISTS pg_stat_statements")
            self._has_pg_stat_statements = True
        except Exception:
            self._conn.rollback()
            print("[lakebase_metrics] pg_stat_statements not available; skipping per-query metrics.")

        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()
        print(f"[lakebase_metrics] Collector started (interval={METRICS_INTERVAL}s)")

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=METRICS_INTERVAL + 2)
        if self._conn:
            try:
                self._conn.close()
            except Exception:
                pass
        print("[lakebase_metrics] Collector stopped.")

    def _loop(self):
        while not self._stop.is_set():
            try:
                self._sample()
            except Exception as e:
                print(f"[lakebase_metrics] Sample error: {e}")
                try:
                    self._conn.close()
                except Exception:
                    pass
                try:
                    self._conn = _connect(self._config)
                    self._conn.autocommit = True
                except Exception:
                    print("[lakebase_metrics] Reconnect failed; stopping collector.")
                    break
            self._stop.wait(METRICS_INTERVAL)

    def _sample(self):
        self._sample_activity()
        self._sample_database()
        self._sample_locks()
        self._sample_tables()
        if self._has_pg_stat_statements:
            self._sample_statements()

    # -- pg_stat_activity: connection counts by state --

    def _sample_activity(self):
        with self._conn.cursor() as cur:
            cur.execute("""
                SELECT state, count(*)
                FROM pg_stat_activity
                WHERE backend_type = 'client backend'
                GROUP BY state
            """)
            rows = cur.fetchall()

        total = 0
        for state, count in rows:
            label = state or "unknown"
            total += count
            self._fire(f"connections/{label}", count)
        self._fire("connections/total", total)

    # -- pg_stat_database: throughput and cache hit ratio --

    def _sample_database(self):
        with self._conn.cursor() as cur:
            cur.execute("""
                SELECT xact_commit, xact_rollback,
                       tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted,
                       blks_hit, blks_read,
                       conflicts, deadlocks, temp_bytes
                FROM pg_stat_database
                WHERE datname = current_database()
            """)
            row = cur.fetchone()
            if not row:
                return

        cols = [
            "xact_commit", "xact_rollback",
            "tup_returned", "tup_fetched", "tup_inserted", "tup_updated", "tup_deleted",
            "blks_hit", "blks_read",
            "conflicts", "deadlocks", "temp_bytes",
        ]
        current = dict(zip(cols, row))

        if self._prev_db_stats:
            prev = self._prev_db_stats
            dt = METRICS_INTERVAL or 1

            commits = (current["xact_commit"] - prev["xact_commit"]) / dt
            rollbacks = (current["xact_rollback"] - prev["xact_rollback"]) / dt
            self._fire("db/commits_per_sec", commits)
            self._fire("db/rollbacks_per_sec", rollbacks)

            for key in ("tup_inserted", "tup_updated", "tup_deleted", "tup_fetched"):
                delta = (current[key] - prev[key]) / dt
                short = key.replace("tup_", "")
                self._fire(f"db/{short}_per_sec", delta)

            blks_hit_d = current["blks_hit"] - prev["blks_hit"]
            blks_read_d = current["blks_read"] - prev["blks_read"]
            total_blks = blks_hit_d + blks_read_d
            if total_blks > 0:
                hit_ratio = blks_hit_d / total_blks * 100
                self._fire("db/cache_hit_ratio_pct", hit_ratio)

            deadlocks_d = current["deadlocks"] - prev["deadlocks"]
            conflicts_d = current["conflicts"] - prev["conflicts"]
            self._fire("db/deadlocks_delta", deadlocks_d)
            self._fire("db/conflicts_delta", conflicts_d)

        self._prev_db_stats = current

    # -- pg_locks: lock contention --

    def _sample_locks(self):
        with self._conn.cursor() as cur:
            cur.execute("""
                SELECT count(*) FILTER (WHERE granted) AS granted,
                       count(*) FILTER (WHERE NOT granted) AS waiting
                FROM pg_locks
            """)
            row = cur.fetchone()
        self._fire("locks/granted", row[0])
        self._fire("locks/waiting", row[1])

    # -- pg_stat_user_tables: table-level I/O --

    def _sample_tables(self):
        with self._conn.cursor() as cur:
            cur.execute("""
                SELECT relname,
                       seq_scan, idx_scan,
                       n_tup_ins, n_tup_upd, n_tup_del,
                       n_live_tup, n_dead_tup
                FROM pg_stat_user_tables
                ORDER BY COALESCE(seq_scan, 0) + COALESCE(idx_scan, 0) DESC
                LIMIT 10
            """)
            rows = cur.fetchall()
        for row in rows:
            table = row[0]
            self._fire(f"table/{table}/seq_scans", row[1] or 0)
            self._fire(f"table/{table}/idx_scans", row[2] or 0)
            self._fire(f"table/{table}/live_tuples", row[6] or 0)
            self._fire(f"table/{table}/dead_tuples", row[7] or 0)

    # -- pg_stat_statements: top queries by total_exec_time delta --

    def _sample_statements(self):
        with self._conn.cursor() as cur:
            cur.execute("""
                SELECT queryid, query, calls, total_exec_time, mean_exec_time,
                       rows, shared_blks_hit, shared_blks_read
                FROM pg_stat_statements
                WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
                ORDER BY total_exec_time DESC
                LIMIT 20
            """)
            rows = cur.fetchall()

        current_stmts = {}
        for qid, query, calls, total_time, mean_time, rows_count, blks_hit, blks_read in rows:
            current_stmts[qid] = {
                "query": query, "calls": calls, "total_exec_time": total_time,
                "mean_exec_time": mean_time, "rows": rows_count,
                "shared_blks_hit": blks_hit, "shared_blks_read": blks_read,
            }

        if self._prev_stmt_stats:
            for qid, cur_s in current_stmts.items():
                prev_s = self._prev_stmt_stats.get(qid)
                if not prev_s:
                    continue
                delta_calls = cur_s["calls"] - prev_s["calls"]
                if delta_calls <= 0:
                    continue
                short_query = cur_s["query"][:60].replace("\n", " ").strip()
                self._fire(f"stmt/{short_query}/calls_delta", delta_calls)
                self._fire(f"stmt/{short_query}/mean_exec_ms", cur_s["mean_exec_time"])

        self._prev_stmt_stats = current_stmts

    # -- Fire metric as a Locust request event --

    def _fire(self, name, value):
        events.request.fire(
            request_type="lakebase_metric",
            name=name,
            response_time=value,
            response_length=0,
            exception=None,
        )


# --- Locust event hooks: auto-start/stop the collector ---

_collector = LakebaseMetricsCollector()


@events.test_start.add_listener
def _on_test_start(environment, **kwargs):
    from locust.runners import MasterRunner, LocalRunner
    runner = environment.runner
    if isinstance(runner, (MasterRunner, LocalRunner)) or runner is None:
        try:
            config = _load_config()
            _collector.start(config)
        except Exception as e:
            print(f"[lakebase_metrics] Failed to start collector: {e}")


@events.test_stop.add_listener
def _on_test_stop(environment, **kwargs):
    _collector.stop()

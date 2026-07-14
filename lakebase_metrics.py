"""
Lakebase server-side metrics collector for Locust load tests.

Periodically samples Postgres system views and exposes them in a dedicated
"Lakebase Server" tab in the Locust web UI (open /lakebase on the master).

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

View metrics: http://<master-host>:8089/lakebase (after starting a test from the UI).

The sampling interval defaults to 5 seconds. Override with:

    LAKEBASE_METRICS_INTERVAL=10 locust -f locust.py

Set LAKEBASE_METRICS_IN_STATS=1 to also emit lakebase_metric rows in the default
Statistics table (not recommended; values are gauges, not latencies).
"""

import json
import os
import threading

import psycopg2
from databricks.sdk import WorkspaceClient
from flask import Blueprint, render_template, request
from locust import events

DEFAULT_DATABASE = "databricks_postgres"
METRICS_INTERVAL = int(os.environ.get("LAKEBASE_METRICS_INTERVAL", "5"))
_EXPORT_TO_STATS = os.environ.get("LAKEBASE_METRICS_IN_STATS", "").lower() in ("1", "true", "yes")
_STMT_METRIC_LIMIT = 20
_UI_TAB_KEY = "lakebase-server"


def _load_config():
    path = os.environ.get("CONFIG_PATH", "config.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _connect(config):
    """Open a monitoring connection to Lakebase autoscale (same config as LakebaseUser)."""
    ws_cfg = config["workspace"]
    ws = WorkspaceClient(
        host=ws_cfg["host"],
        client_id=ws_cfg["client_id"],
        client_secret=ws_cfg["client_secret"],
    )
    lakebase = config["lakebase"]
    project_id = lakebase.get("project_id")
    branch_id = lakebase.get("branch_id")
    endpoint_id = lakebase.get("endpoint_id")
    if not project_id or not branch_id or not endpoint_id:
        raise ValueError(
            "lakebase.project_id, lakebase.branch_id and lakebase.endpoint_id are required"
        )
    database = lakebase.get("database") or DEFAULT_DATABASE
    user = lakebase["user"]
    endpoint_name = f"projects/{project_id}/branches/{branch_id}/endpoints/{endpoint_id}"
    endpoint = ws.postgres.get_endpoint(name=endpoint_name)
    host = None
    if endpoint.status and endpoint.status.hosts:
        host = endpoint.status.hosts.host
    if not host:
        raise ValueError(f"Endpoint {endpoint_name} has no host; endpoint may not be ready")
    cred = ws.postgres.generate_database_credential(endpoint=endpoint_name)
    return psycopg2.connect(
        host=host,
        dbname=database,
        user=user,
        password=cred.token,
        sslmode="require",
    )


def _infer_group_and_unit(name: str) -> tuple[str, str]:
    group = name.split("/", 1)[0]
    if name.endswith("_per_sec"):
        unit = "/s"
    elif name.endswith("_pct"):
        unit = "%"
    elif name.endswith("_ms"):
        unit = "ms"
    elif name.endswith("_delta"):
        unit = "delta"
    else:
        unit = "count"
    return group, unit


class LakebaseMetricsCollector:
    """Samples Lakebase server-side metrics for the Locust web UI."""

    def __init__(self):
        self._conn = None
        self._config = None
        self._has_pg_stat_statements = False
        self._stop = threading.Event()
        self._thread = None
        self._prev_db_stats = None
        self._prev_stmt_stats = {}
        self._metrics_lock = threading.Lock()
        self._latest_metrics: dict[str, dict] = {}

    def get_stats_rows(self) -> list[dict]:
        with self._metrics_lock:
            rows = [
                {
                    "metric": name,
                    "value": round(entry["value"], 4) if isinstance(entry["value"], float) else entry["value"],
                    "unit": entry["unit"],
                    "group": entry["group"],
                }
                for name, entry in self._latest_metrics.items()
                if not name.startswith("stmt/")
            ]
            stmt_rows = [
                {
                    "metric": name,
                    "value": round(entry["value"], 4) if isinstance(entry["value"], float) else entry["value"],
                    "unit": entry["unit"],
                    "group": entry["group"],
                }
                for name, entry in self._latest_metrics.items()
                if name.startswith("stmt/")
            ]
        rows.sort(key=lambda r: (r["group"], r["metric"]))
        stmt_rows.sort(key=lambda r: r["metric"])
        return rows + stmt_rows[:_STMT_METRIC_LIMIT]

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
        print(
            f"[lakebase_metrics] Collector started (interval={METRICS_INTERVAL}s). "
            f"Open /lakebase in the Locust UI for server metrics."
        )

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

    def _fire(self, name, value):
        group, unit = _infer_group_and_unit(name)
        with self._metrics_lock:
            self._latest_metrics[name] = {"value": value, "unit": unit, "group": group}

        if _EXPORT_TO_STATS:
            events.request.fire(
                request_type="lakebase_metric",
                name=name,
                response_time=value,
                response_length=0,
                exception=None,
            )


_collector = LakebaseMetricsCollector()
_lakebase_ui = Blueprint("lakebase_metrics_ui", __name__)


def _lakebase_template_args(environment):
    environment.web_ui.update_template_args()
    return {
        **environment.web_ui.template_args,
        "extended_tabs": [{"title": "Lakebase Server", "key": _UI_TAB_KEY}],
        "extended_tables": [
            {
                "key": _UI_TAB_KEY,
                "structure": [
                    {"key": "metric", "title": "Metric"},
                    {"key": "value", "title": "Value"},
                    {"key": "unit", "title": "Unit"},
                    {"key": "group", "title": "Group"},
                ],
            }
        ],
    }


@events.init.add_listener
def _register_lakebase_ui(environment, **kwargs):
    if not environment.web_ui:
        return

    @environment.web_ui.app.after_request
    def _inject_extended_stats(response):
        if request.path != "/stats/requests":
            return response
        if not response.content_type or "json" not in response.content_type:
            return response
        try:
            payload = response.get_json()
        except Exception:
            return response
        if not isinstance(payload, dict):
            return response
        payload["extended_stats"] = [
            {"key": _UI_TAB_KEY, "data": _collector.get_stats_rows()}
        ]
        response.set_data(json.dumps(payload))
        response.content_type = "application/json"
        return response

    @_lakebase_ui.route("/lakebase")
    def _lakebase_web_ui():
        return render_template(
            "index.html",
            template_args=_lakebase_template_args(environment),
        )

    environment.web_ui.app.register_blueprint(_lakebase_ui)


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

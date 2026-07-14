# Locust workers use gevent. monkey.patch_all() alone is not enough: psycopg2/libpq uses
# blocking C I/O that bypasses patched sockets, so heartbeats stall and the master drops workers.
from gevent import monkey

monkey.patch_all()

from psycogreen.gevent import patch_psycopg

patch_psycopg()

import lakebase_metrics  # noqa: F401

import logging
import os
import random
from collections import deque
from itertools import count

from lakebase_user import LakebaseUser, lakebase_task

_INSERT_SEQ = count(1)
_INSERTED_ID_MAX = 10_000
_DEBUG = os.environ.get("LOCUST_DEBUG", "").lower() in ("1", "true", "yes")

_CREATE_TABLE_SQL = """
    CREATE TABLE IF NOT EXISTS test_table (
        inserted_id VARCHAR(64) PRIMARY KEY,
        name VARCHAR(255)
    )
"""
_INSERT_SQL = "INSERT INTO test_table(inserted_id, name) VALUES (%s, %s)"
_SELECT_SQL = "SELECT name FROM test_table WHERE inserted_id = %s"
_UPDATE_SQL = "UPDATE test_table SET name=%s WHERE inserted_id = %s"
_DELETE_SQL = "DELETE FROM test_table WHERE inserted_id = %s"


def _debug(msg: str) -> None:
    if _DEBUG:
        print(msg, flush=True)


def _resolve_worker_id(runner) -> str:
    if runner is None:
        return "0"
    idx = getattr(runner, "worker_index", -1)
    return str(idx) if idx >= 0 else "0"


class MyUser(LakebaseUser):

    def __init__(self, environment):
        super().__init__(environment)
        self.inserted_id = deque(maxlen=_INSERTED_ID_MAX)
        self._worker_id = None

    def on_start(self):
        super().on_start()
        runner = self.environment.runner
        idx = getattr(runner, "worker_index", -1) if runner else -1
        if idx < 0:
            logging.warning(
                "worker_index not set yet (expected >= 0); using worker id 0. "
                "Distributed PKs may collide until the worker ACKs the master."
            )
        self._worker_id = _resolve_worker_id(runner)
        self.run_sql(_CREATE_TABLE_SQL)
        _debug("created table")

    def _next_row_id(self) -> str:
        if self._worker_id == "0":
            resolved = _resolve_worker_id(self.environment.runner)
            if resolved != "0":
                self._worker_id = resolved
        return f"{self._worker_id}-{next(_INSERT_SEQ)}"

    @lakebase_task()
    def insert_record(self):
        row_id = self._next_row_id()
        name = f"u{row_id}"
        self.run_sql(_INSERT_SQL, (row_id, name), commit=True)
        self.inserted_id.append(row_id)
        _debug(f"inserted id {row_id} name={name}")

    @lakebase_task()
    def select_record(self):
        if not self.inserted_id:
            return
        row_id = random.choice(self.inserted_id)
        self.run_sql(_SELECT_SQL, (row_id,))
        _debug(f"selected record {row_id}")

    @lakebase_task()
    def update_record(self):
        if not self.inserted_id:
            return
        row_id = random.choice(self.inserted_id)
        new_name = f"u{row_id}x"
        self.run_sql(_UPDATE_SQL, (new_name, row_id), commit=True)
        _debug(f"updated id {row_id} name={new_name}")

    @lakebase_task()
    def delete_record(self):
        if not self.inserted_id:
            return
        row_id = random.choice(self.inserted_id)
        self.run_sql(_DELETE_SQL, (row_id,), commit=True)
        self.inserted_id.remove(row_id)
        _debug(f"deleted id {row_id}")

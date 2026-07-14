# Locust workers use gevent. monkey.patch_all() alone is not enough: psycopg2/libpq uses
# blocking C I/O that bypasses patched sockets, so heartbeats stall and the master drops workers.
from gevent import monkey

monkey.patch_all()

from psycogreen.gevent import patch_psycopg

patch_psycopg()

import logging
import os
import random
from collections import deque

from lakebase_user import LakebaseUser, lakebase_task

# Per-worker range for INTEGER PKs: high bits = worker slot, low 20 bits = random (fits signed int32).
_ROW_ID_LOW_BITS = 20
_ROW_ID_LOW_MASK = (1 << _ROW_ID_LOW_BITS) - 1
# 2048 worker slots (0..2047); slot * 2^20 + (2^20-1) <= 2^31-1
_WORKER_SLOT_MOD = (2**31 - 1) // (1 << _ROW_ID_LOW_BITS) + 1

_CREATE_TABLE_SQL = """
    CREATE TABLE IF NOT EXISTS test_table (
        inserted_id INTEGER PRIMARY KEY,
        name VARCHAR(255)
    )
"""
_INSERT_SQL = "INSERT INTO test_table(inserted_id, name) VALUES (%s, %s)"
_SELECT_SQL = "SELECT name FROM test_table WHERE inserted_id = %s"
_UPDATE_SQL = "UPDATE test_table SET name=%s WHERE inserted_id=%s"
_DELETE_SQL = "DELETE FROM test_table WHERE inserted_id=%s"

# Keep recent ids only so long runs do not grow memory and slow random.choice.
_INSERTED_ID_MAX = 10_000
_DEBUG = os.environ.get("LOCUST_DEBUG", "").lower() in ("1", "true", "yes")


def _debug(msg: str) -> None:
    if _DEBUG:
        print(msg, flush=True)


class MyUser(LakebaseUser):

    def __init__(self, environment):
        super().__init__(environment)
        self.inserted_id = deque(maxlen=_INSERTED_ID_MAX)
        self._row_id_prefix = 0

    def on_start(self):
        super().on_start()
        worker_index = self.environment.runner.worker_index
        if worker_index < 0:
            logging.warning(
                "worker_index not set yet (expected >= 0); using slot 0. "
                "Distributed PKs may collide until the worker ACKs the master."
            )
            worker_index = 0
        self._row_id_prefix = (worker_index % _WORKER_SLOT_MOD) << _ROW_ID_LOW_BITS
        self.run_sql(_CREATE_TABLE_SQL)
        _debug("created table")

    @lakebase_task()
    def insert_record(self):
        row_id = self._row_id_prefix | random.getrandbits(_ROW_ID_LOW_BITS)
        if row_id == 0:
            row_id = 1
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

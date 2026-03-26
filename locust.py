# Locust workers use gevent. monkey.patch_all() alone is not enough: psycopg2/libpq uses
# blocking C I/O that bypasses patched sockets, so heartbeats stall and the master drops workers.
from gevent import monkey

monkey.patch_all()

from psycogreen.gevent import patch_psycopg

patch_psycopg()

from locust import between
from locust.runners import WorkerRunner
import random
import uuid

from faker import Faker

from lakebase_user import LakebaseUser, lakebase_task

# Per-worker range for INTEGER PKs: high bits = worker slot, low 20 bits = random (fits signed int32).
_ROW_ID_LOW_BITS = 20
_ROW_ID_LOW_MASK = (1 << _ROW_ID_LOW_BITS) - 1
# 2048 worker slots (0..2047); slot * 2^20 + (2^20-1) <= 2^31-1
_WORKER_SLOT_MOD = (2**31 - 1) // (1 << _ROW_ID_LOW_BITS) + 1


class MyUser(LakebaseUser):

    def __init__(self, environment):
        super().__init__(environment)
        self.faker = Faker()
        self.inserted_id = []  # list of inserted_id values (unique across workers)

    def _worker_slot(self) -> int:
        runner = self.environment.runner
        if isinstance(runner, WorkerRunner):
            return runner.worker_index % _WORKER_SLOT_MOD
        return 0

    def on_start(self):
        super().on_start()
        self.inserted_id = []
        self.run_sql("""
            CREATE TABLE IF NOT EXISTS test_table (
                inserted_id INTEGER PRIMARY KEY,
                name VARCHAR(255)
            )
        """)
        print("created table")

    @lakebase_task()
    def insert_record(self):
        # Namespace ids by Locust worker so distributed workers avoid PRIMARY KEY collisions.
        row_id = self._worker_slot() * (1 << _ROW_ID_LOW_BITS) + (
            uuid.uuid4().int & _ROW_ID_LOW_MASK
        )
        if row_id == 0:
            row_id = 1
        name = self.faker.name()
        sql = "INSERT INTO test_table(inserted_id, name) VALUES (%s, %s)"
        self.run_sql(sql, [row_id, name], commit=True)
        self.inserted_id.append(row_id)
        print(f"inserted id {row_id} name={name}")

    @lakebase_task()
    def select_record(self):
        if not self.inserted_id:
            return
        sql = "SELECT name FROM test_table WHERE inserted_id = %s"
        id = random.choice(self.inserted_id)
        name = self.run_sql(sql, [id])
        print(f"selected record {id} name={name}")
    
    @lakebase_task()
    def update_record(self):
        if not self.inserted_id:
            return
        idx = random.randint(0, len(self.inserted_id) - 1)
        row_id = self.inserted_id[idx]
        new_name = self.faker.name()
        sql = "UPDATE test_table SET name=%s WHERE inserted_id=%s"
        self.run_sql(sql, (new_name, row_id), commit=True)
        print(f"updated id {row_id} name={new_name}")

    @lakebase_task()
    def delete_record(self):
        if not self.inserted_id:
            return
        to_be_removed = random.randint(0, len(self.inserted_id) - 1)
        removed_id = self.inserted_id[to_be_removed]
        sql = "DELETE FROM test_table WHERE inserted_id=%s"
        self.run_sql(sql, (removed_id,), commit=True)
        self.inserted_id.pop(to_be_removed)
        print(f"deleted id {removed_id}")

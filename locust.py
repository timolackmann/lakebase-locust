from locust import between
import random
import uuid

from faker import Faker

from lakebase_user import LakebaseUser, lakebase_task


class MyUser(LakebaseUser):

    def __init__(self, environment):
        super().__init__(environment)
        self.faker = Faker()
        self.inserted_id = []  # list of inserted_id values (unique across workers)

    def on_start(self):
        super().on_start()
        self.inserted_id = []
        self.run_sql("""
            CREATE TABLE IF NOT EXISTS test_table2 (
                inserted_id INTEGER PRIMARY KEY,
                name VARCHAR(255)
            )
        """)
        print("created table")

    @lakebase_task()
    def insert_record(self):
        # Use a unique id across workers to avoid UniqueViolation with multiple Locust workers
        row_id = uuid.uuid4().int % (2**31 - 1) or 1
        name = self.faker.name()
        sql = "INSERT INTO test_table2(inserted_id, name) VALUES (%s, %s)"
        self.run_sql(sql, [row_id, name], commit=True)
        self.inserted_id.append(row_id)
        print(f"inserted id {row_id} name={name}")

    @lakebase_task()
    def update_record(self):
        if not self.inserted_id:
            return
        idx = random.randint(0, len(self.inserted_id) - 1)
        row_id = self.inserted_id[idx]
        new_name = self.faker.name()
        sql = "UPDATE test_table2 SET name=%s WHERE inserted_id=%s"
        self.run_sql(sql, (new_name, row_id), commit=True)
        print(f"updated id {row_id} name={new_name}")

    @lakebase_task()
    def delete_record(self):
        if not self.inserted_id:
            return
        to_be_removed = random.randint(0, len(self.inserted_id) - 1)
        removed_id = self.inserted_id[to_be_removed]
        sql = "DELETE FROM test_table2 WHERE inserted_id=%s"
        self.run_sql(sql, (removed_id,), commit=True)
        self.inserted_id.pop(to_be_removed)
        print(f"deleted id {removed_id}")

from locust import between, task
import random

from lakebase_user import LakebaseUser


class MyUser(LakebaseUser):

    def __init__(self, environment):
        super().__init__(environment)
        self.latest_id = 1
        self.inserted_id = []

    def on_start(self):
        super().on_start()
        self.latest_id = 1
        self.inserted_id = []

        command = """
            CREATE TABLE test_table2 (
                inserted_id INTEGER PRIMARY KEY,
                name VARCHAR(255)
            )
            """

        def create_table(cur):
            cur.execute(command)

        self.execute_timed("create_table", lambda: self._run_with_cursor(create_table))
        print("created table")

    def _run_with_cursor(self, operation):
        with self.conn.cursor() as cur:
            operation(cur)

    @task()
    def insert_record(self):
        command = "INSERT INTO test_table2(inserted_id) VALUES (%s)"

        def do_insert(cur):
            cur.execute(command, [self.latest_id])

        self.execute_timed("insert_record", lambda: self._run_with_cursor(do_insert), commit=True)
        self.inserted_id.append(self.latest_id)
        self.latest_id += 1
        print(f"inserted id {self.latest_id}")

    @task()
    def delete_record(self):
        if not self.inserted_id:
            return
        to_be_removed = random.randint(0, len(self.inserted_id) - 1)
        command = "DELETE FROM test_table2 WHERE inserted_id=%s;"
        removed_id = self.inserted_id[to_be_removed]

        def do_delete(cur):
            cur.execute(command, (removed_id,))

        self.execute_timed("delete_record", lambda: self._run_with_cursor(do_delete), commit=True)
        self.inserted_id.pop(to_be_removed)
        print(f"deleted id {removed_id}")

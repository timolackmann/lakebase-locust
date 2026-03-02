# Base image to run Locust with Lakebase (PostgreSQL) load-test dependencies.
# Build from repo root: docker build -f k8s/Dockerfile -t locust-lakebase:latest .
# lakebase_user.py is in the image; only locust.py is mounted at /mnt/locust in Kubernetes.
# Config: mount config.json or set CONFIG_PATH at runtime.

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app

WORKDIR /mnt/locust

# Dependencies and shared Lakebase user (mounted locust.py imports this)
COPY k8s/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt
COPY lakebase_user.py /app/lakebase_user.py

EXPOSE 8089
# Same image for master and worker. Set LOCUST_OPTIONS in Kubernetes:
#   master:  LOCUST_OPTIONS="--master"
#   worker:  LOCUST_OPTIONS="--worker --master-host master"
# Default (no env): --host https://localhost for local/docker runs
CMD ["sh", "-c", "exec locust -f locust.py ${LOCUST_OPTIONS}"]

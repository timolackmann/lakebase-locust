# Base image to run Locust with Lakebase (PostgreSQL) load-test dependencies.
# Build from repo root: docker build -f k8s/Dockerfile -t locust-lakebase:latest .
# lakebase_user.py is in the image; only locust.py is mounted at /mnt/locust in Kubernetes.
# Config: mount config.json or set CONFIG_PATH at runtime.

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app

WORKDIR /mnt/locust

# Pip inside the build does not read the host's pip.conf; optional index / trusted-host via build-args.
# build-and-push.sh forwards from PIP_* env or `pip3 config get global.*`.
# Flags are only added when non-empty so default PyPI is unchanged if args are omitted.
ARG PIP_INDEX_URL
ARG PIP_EXTRA_INDEX_URL
ARG PIP_TRUSTED_HOST

# Dependencies and shared Lakebase user (mounted locust.py imports this)
COPY requirements.txt /tmp/requirements.txt
RUN set -e; \
    opts=""; \
    if [ -n "$PIP_INDEX_URL" ]; then opts="$opts --index-url=$PIP_INDEX_URL"; fi; \
    if [ -n "$PIP_EXTRA_INDEX_URL" ]; then opts="$opts --extra-index-url=$PIP_EXTRA_INDEX_URL"; fi; \
    if [ -n "$PIP_TRUSTED_HOST" ]; then opts="$opts --trusted-host=$PIP_TRUSTED_HOST"; fi; \
    pip install --no-cache-dir $opts -r /tmp/requirements.txt && rm /tmp/requirements.txt
COPY lakebase_user.py /app/lakebase_user.py

EXPOSE 8089
# Same image for master and worker. Set LOCUST_OPTIONS in Kubernetes:
#   master:  LOCUST_OPTIONS="--master"
#   worker:  LOCUST_OPTIONS="--worker --master-host master"
# Default (no env): --host https://localhost for local/docker runs
CMD ["sh", "-c", "exec locust -f locust.py ${LOCUST_OPTIONS}"]

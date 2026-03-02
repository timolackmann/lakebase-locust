#!/usr/bin/env python3

"""
WORK IN PROGRESS

This script is not yet working.
"""
"""
Setup script for Locust + Lakebase: creates a Databricks service principal,
adds client_id and client_secret to config.json, and grants the service principal
OAuth access to the Lakebase Postgres instance.

All operations use the workspace-level Databricks CLI (no account-level commands).

Prerequisites:
- Databricks CLI installed and authenticated (workspace profile).
- config.json (or CONFIG_PATH) with workspace.host and lakebase section (mode, project_id/branch_id/endpoint_id or instance_names).

Usage:
  python setup_service_principal.py [--profile PROFILE] [--display-name NAME] [--config PATH]
"""

import argparse
import json
import os
import subprocess
import sys


def run_cli(*args, profile: str, output_json: bool = True):
    cmd = ["databricks"] + list(args) + ["-p", profile]
    if output_json:
        cmd.extend(["-o", "json"])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Databricks CLI failed: {result.stderr or result.stdout}")
    return json.loads(result.stdout) if output_json and result.stdout.strip() else result.stdout.strip()


def load_config(path: str):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_config(path: str, config: dict):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description="Create service principal and add to config + Lakebase Postgres")
    parser.add_argument("--profile", default=os.environ.get("DATABRICKS_CLI_PROFILE", "DEFAULT"), help="Databricks CLI profile")
    parser.add_argument("--display-name", default="locust-lakebase-sp", help="Service principal display name")
    parser.add_argument("--config", default=os.environ.get("CONFIG_PATH", "config.json"), help="Config file path")
    args = parser.parse_args()

    config_path = args.config
    if not os.path.isfile(config_path):
        print(f"Config not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    config = load_config(config_path)
    workspace = config.get("workspace") or {}
    lakebase = config.get("lakebase") or {}
    if not workspace.get("host"):
        print("config.workspace.host is required.", file=sys.stderr)
        sys.exit(1)
    if not lakebase:
        print("config.lakebase is required (mode, project_id/branch_id/endpoint_id or instance_names).", file=sys.stderr)
        sys.exit(1)

    host = workspace["host"].rstrip("/").replace("https://", "").replace("http://", "")
    profile = args.profile
    display_name = args.display_name

    # 1) Create service principal (workspace) — SCIM API expects camelCase (displayName, not display_name)
    print("Creating service principal...")
    try:
        sp = run_cli("service-principals", "create", "--json", json.dumps({"displayName": display_name, "active": True}), profile=profile)
    except Exception as e:
        print(f"Failed to create service principal: {e}", file=sys.stderr)
        sys.exit(1)

    # API may return applicationId (camelCase) or application_id (snake_case)
    client_id = sp.get("application_id") or sp.get("applicationId")
    sp_id = sp.get("id")
    if not client_id:
        print("Service principal response missing application_id/applicationId.", file=sys.stderr)
        sys.exit(1)
    print(f"  client_id (application_id): {client_id}")

    # 2) Create OAuth secret (workspace CLI: service-principal-secrets-proxy)
    # CLI sometimes returns "User is not authorized to perform this operation." even when it succeeds, so we
    # verify we got a secret and retry once if not.
    client_secret = None
    last_error = None
    for attempt in range(2):
        try:
            secret_out = run_cli("service-principal-secrets-proxy", "create", str(sp_id), profile=profile)
            if isinstance(secret_out, dict):
                client_secret = secret_out.get("secret") or secret_out.get("value") or secret_out.get("client_secret")
            if not client_secret and isinstance(secret_out, str):
                client_secret = secret_out
            if client_secret:
                break
            last_error = "No secret in create response"
        except Exception as e:
            last_error = e
            if attempt == 0 and "not authorized" in str(e).lower():
                print("Secret create returned authorization error, retrying once...", file=sys.stderr)
            elif attempt == 1:
                break
        if not client_secret and attempt == 0:
            print("Secret not created or not returned, retrying once...", file=sys.stderr)

    if not client_secret:
        print("Could not read client_secret from service-principal-secrets-proxy create output. Add it manually to config.", file=sys.stderr)
        if last_error:
            print(f"Last error: {last_error}", file=sys.stderr)
        print("Run: databricks service-principal-secrets-proxy create", sp_id, "-p", profile, "-o json", file=sys.stderr)
        print("Create a secret in the workspace UI (Service Principal → Secrets) or run:", file=sys.stderr)
        print("  databricks service-principal-secrets-proxy create", sp_id, "-p", profile, file=sys.stderr)
        print("Then add client_secret to config.json and re-run this script to add the SP to Postgres.", file=sys.stderr)
        if not workspace.get("client_id"):
            sys.exit(1)

    # 3) Update config.json
    workspace["client_id"] = client_id
    if client_secret:
        workspace["client_secret"] = client_secret
    lakebase["user"] = client_id
    config["workspace"] = workspace
    config["lakebase"] = lakebase
    save_config(config_path, config)
    print(f"Updated {config_path} with client_id and lakebase.user.")

    # 4) Add service principal to Postgres (create role so OAuth can be used)
    mode = lakebase.get("mode", "provisioned")
    database_name = lakebase.get("database") or "databricks_postgres"

    try:
        import psycopg2
    except ImportError:
        print("psycopg2 not installed; skipping Postgres role creation. Install with: pip install psycopg2-binary", file=sys.stderr)
        return

    if mode == "autoscale":
        project_id = lakebase.get("project_id")
        branch_id = lakebase.get("branch_id")
        endpoint_id = lakebase.get("endpoint_id")
        if not all((project_id, branch_id, endpoint_id)):
            print("lakebase.project_id, branch_id, endpoint_id required for autoscale.", file=sys.stderr)
            return
        branch_path = f"projects/{project_id}/branches/{branch_id}"
        endpoint_path = f"{branch_path}/endpoints/{endpoint_id}"
        # Get host and token as current user (profile)
        endpoints = run_cli("postgres", "list-endpoints", branch_path, profile=profile)
        if isinstance(endpoints, list) and endpoints:
            host_pg = endpoints[0].get("status", {}).get("hosts", {}).get("host")
        else:
            print("Could not get postgres endpoint host.", file=sys.stderr)
            return
        cred = run_cli("postgres", "generate-database-credential", endpoint_path, profile=profile)
        token = cred.get("token") if isinstance(cred, dict) else cred
        if not token:
            print("Could not get database credential token.", file=sys.stderr)
            return
        current_user = run_cli("current-user", "me", profile=profile)
        user_email = (current_user.get("userName") or (current_user.get("emails") or [{}])[0].get("value") if current_user.get("emails") else None) if isinstance(current_user, dict) else None
        if not user_email:
            print("Could not get current user for Postgres connection.", file=sys.stderr)
            return
        conn = psycopg2.connect(
            host=host_pg,
            port=5432,
            dbname=database_name,
            user=user_email,
            password=token,
            sslmode="require",
        )
    else:
        # Provisioned: instance_names, use CLI for credential and instance details
        instance_names = lakebase.get("instance_names") or []
        if not instance_names:
            print("lakebase.instance_names required for provisioned mode.", file=sys.stderr)
            return
        instance_name = instance_names[0]
        instance = run_cli("database", "get-database-instance", instance_name, profile=profile)
        if isinstance(instance, dict):
            host_pg = instance.get("read_write_dns") or next((instance.get(k) for k in ("host", "endpoint") if instance.get(k)), None)
        else:
            host_pg = None
        if not host_pg:
            print("Could not get provisioned instance host from get-database-instance.", file=sys.stderr)
            return
        import uuid
        cred_payload = json.dumps({"instance_names": instance_names})
        cred = run_cli("database", "generate-database-credential", "--request-id", str(uuid.uuid4()), "--json", cred_payload, profile=profile)
        token = cred.get("token") if isinstance(cred, dict) else cred
        if not token:
            print("Could not get database credential token for provisioned instance.", file=sys.stderr)
            return
        current_user = run_cli("current-user", "me", profile=profile)
        user_email = (current_user.get("userName") or (current_user.get("emails") or [{}])[0].get("value") if current_user.get("emails") else None) if isinstance(current_user, dict) else None
        if not user_email:
            print("Could not get current user for Postgres connection.", file=sys.stderr)
            return
        conn = psycopg2.connect(
            host=host_pg,
            port=5432,
            dbname=database_name,
            user=user_email,
            password=token,
            sslmode="require",
        )

    # Create role for service principal (OAuth user = client_id) and grant access
    role_name = str(client_id)
    with conn.cursor() as cur:
        cur.execute("CREATE EXTENSION IF NOT EXISTS databricks_auth;")
        cur.execute('SELECT 1 FROM pg_roles WHERE rolname = %s', (role_name,))
        if cur.fetchone():
            print(f"Postgres role {role_name!r} already exists.")
        else:
            cur.execute(f"SELECT databricks_create_role('{role_name}', 'SERVICE_PRINCIPAL')")
            print(f"Created Postgres role {role_name!r}.")
        cur.execute(f'GRANT ALL PRIVILEGES ON DATABASE "{database_name}" TO "{role_name}"')
        cur.execute(f'GRANT USAGE, CREATE ON SCHEMA public TO "{role_name}"')
        conn.commit()
    conn.close()
    print(f"Service principal {client_id!r} granted OAuth access to Lakebase Postgres database {database_name!r}.")


if __name__ == "__main__":
    main()

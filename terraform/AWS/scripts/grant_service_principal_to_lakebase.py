#!/usr/bin/env python3
"""
Grant a Databricks service principal OAuth access to a Lakebase Postgres instance by
running SQL on the Postgres database (CREATE EXTENSION databricks_auth, create role, GRANTs).

Can be run manually after Terraform apply, or from Terraform via null_resource local-exec.

Prerequisites:
- Databricks CLI installed and authenticated (workspace profile).
- psycopg2-binary: pip install psycopg2-binary

Usage (manual):
  python grant_service_principal_to_lakebase.py \\
    --project-id PROJECT_ID --branch-id BRANCH_ID --endpoint-id ENDPOINT_ID \\
    --service-principal-id APPLICATION_ID [--profile PROFILE] [--database DB]

Usage (from Terraform, script dir = terraform/AWS/scripts):
  python grant_service_principal_to_lakebase.py \\
    --project-id "$TF_VAR_project_id" --branch-id "$TF_VAR_branch_id" \\
    --endpoint-id "$TF_VAR_endpoint_id" --service-principal-id "$TF_VAR_service_principal_id" \\
    --profile "$TF_VAR_databricks_profile" --database "$TF_VAR_database"
"""

import argparse
import json
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


def main():
    parser = argparse.ArgumentParser(
        description="Grant service principal OAuth access to Lakebase Postgres via SQL"
    )
    parser.add_argument("--project-id", required=True, help="Lakebase project ID")
    parser.add_argument("--branch-id", required=True, help="Lakebase branch ID")
    parser.add_argument("--endpoint-id", required=True, help="Lakebase endpoint ID")
    parser.add_argument(
        "--service-principal-id",
        required=True,
        help="Service principal application_id (OAuth client_id)",
    )
    parser.add_argument(
        "--profile",
        default="DEFAULT",
        help="Databricks CLI profile (default: DEFAULT)",
    )
    parser.add_argument(
        "--database",
        default="databricks_postgres",
        help="Postgres database name (default: databricks_postgres)",
    )
    args = parser.parse_args()

    try:
        import psycopg2
        from psycopg2 import sql
    except ImportError:
        print("psycopg2 not installed. Install with: pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)

    branch_path = f"projects/{args.project_id}/branches/{args.branch_id}"
    endpoint_path = f"{branch_path}/endpoints/{args.endpoint_id}"

    # Get endpoint host via CLI
    endpoints = run_cli("postgres", "list-endpoints", branch_path, profile=args.profile)
    if isinstance(endpoints, list) and endpoints:
        host_pg = endpoints[0].get("status", {}).get("hosts", {}).get("host")
    else:
        print("Could not get postgres endpoint host from list-endpoints.", file=sys.stderr)
        sys.exit(1)
    if not host_pg:
        print("Endpoint has no host; endpoint may not be ready yet.", file=sys.stderr)
        sys.exit(1)

    # Get short-lived credential for Postgres
    cred = run_cli("postgres", "generate-database-credential", endpoint_path, profile=args.profile)
    token = cred.get("token") if isinstance(cred, dict) else cred
    if not token:
        print("Could not get database credential token.", file=sys.stderr)
        sys.exit(1)

    # Connect as current user (profile) to run SQL
    current_user = run_cli("current-user", "me", profile=args.profile)
    user_email = None
    if isinstance(current_user, dict):
        user_email = current_user.get("userName") or (
            (current_user.get("emails") or [{}])[0].get("value") if current_user.get("emails") else None
        )
    if not user_email:
        print("Could not get current user for Postgres connection.", file=sys.stderr)
        sys.exit(1)

    conn = psycopg2.connect(
        host=host_pg,
        port=5432,
        dbname=args.database,
        user=user_email,
        password=token,
        sslmode="require",
    )

    role_name = args.service_principal_id
    db_name = args.database
    with conn.cursor() as cur:
        cur.execute("CREATE EXTENSION IF NOT EXISTS databricks_auth;")
        cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role_name,))
        if cur.fetchone():
            print(f"Postgres role {role_name!r} already exists.")
        else:
            cur.execute(
                sql.SQL("SELECT databricks_create_role({}, 'SERVICE_PRINCIPAL')").format(
                    sql.Literal(role_name)
                )
            )
            print(f"Created Postgres role {role_name!r}.")
        cur.execute(
            sql.SQL("GRANT ALL PRIVILEGES ON DATABASE {} TO {}").format(
                sql.Identifier(db_name), sql.Identifier(role_name)
            )
        )
        cur.execute(
            sql.SQL("GRANT USAGE, CREATE ON SCHEMA public TO {}").format(sql.Identifier(role_name))
        )
        conn.commit()
    conn.close()
    print(
        f"Service principal {args.service_principal_id!r} granted OAuth access to Lakebase Postgres database {args.database!r}."
    )


if __name__ == "__main__":
    main()

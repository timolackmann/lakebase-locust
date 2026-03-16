# Grant service principal to Lakebase Postgres (OAuth)

To use the Terraform-created **service principal** with **Lakebase Postgres** via OAuth, the SP must be added as a Postgres role. That requires running SQL on the Postgres instance.

## How it works

1. **Connect to Postgres**: Lakebase uses short-lived OAuth tokens. The script uses the Databricks CLI (with your profile) to get an endpoint host and a token via `postgres generate-database-credential`.
2. **Run SQL**: It connects as your current user and runs:
   - `CREATE EXTENSION IF NOT EXISTS databricks_auth;`
   - `SELECT databricks_create_role('<application_id>', 'SERVICE_PRINCIPAL');`
   - `GRANT ALL PRIVILEGES ON DATABASE ...` and `GRANT USAGE, CREATE ON SCHEMA public TO ...`

## Option 1: Run the script manually

After `terraform apply`, create a branch and endpoint in the Lakebase project (UI or CLI) if you don’t have them yet. Then:

```bash
cd terraform/AWS
python3 scripts/grant_service_principal_to_lakebase.py \
  --project-id "$(terraform output -raw lakebase_project_id)" \
  --branch-id "<your-branch-id>" \
  --endpoint-id "<your-endpoint-id>" \
  --service-principal-id "$(terraform output -raw databricks_service_principal_id)" \
  --profile "<your-databricks-profile>" \
  --database "databricks_postgres"
```

**Prerequisites**: Databricks CLI authenticated (`databricks auth login`), `psycopg2-binary` installed.

## Option 2: Run from Terraform (optional)

1. Create the branch and endpoint (e.g. in UI), then set in `terraform.tfvars`:
   - `lakebase_branch_id = "<branch-id>"`
   - `lakebase_endpoint_id = "<endpoint-id>"`
   - `run_grant_sp_to_lakebase = true`
2. Run `terraform apply` again. A `null_resource` will run the script so the service principal is granted access.

The script is idempotent: if the role already exists, it only re-applies the GRANTs.

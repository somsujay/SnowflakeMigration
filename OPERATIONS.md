# Operations Guide

## Overview

This project deploys a Teradata-to-Snowflake migration pipeline with a Bronze/Silver/Gold medallion architecture. Schema changes are managed by **schemachange** — an open-source, version-controlled database migration tool for Snowflake. All migrations live in the `banking/` directory and are parameterized via Jinja2 templating for multi-environment support.

---

## Prerequisites

### Local Development

1. **Python 3.11+** with dependencies: `pip install -r requirements.txt`
2. **Snowflake CLI** (`snow`): `pip install snowflake-cli-labs`
3. **Key-pair auth**: RSA private key at `~/.snowflake/ci_key.p8` (or set `SNOWFLAKE_PRIVATE_KEY_PATH`)
4. **Environment variables**:
   ```bash
   export SNOWFLAKE_ACCOUNT=<your_account>
   export SNOWFLAKE_USER=<your_user>
   ```

### CI/CD (GitHub Actions)

Set these **repository secrets** (Settings > Secrets and variables > Actions):

| Secret | Description |
|--------|-------------|
| `SNOWFLAKE_ACCOUNT` | Account identifier (e.g., `KXAXARZ-GW22129`) |
| `SNOWFLAKE_USER` | Snowflake username (e.g., `SOMSUJAY`) |
| `SNOWFLAKE_PRIVATE_KEY` | Contents of the `.p8` private key file |

For the **production** environment, also set:
- `SNOWFLAKE_PROD_ACCOUNT`
- `SNOWFLAKE_PROD_USER`
- `SNOWFLAKE_PROD_PRIVATE_KEY`

---

## Environment Configuration

All environments are defined in `environments.yml`:

| Environment | Database | Warehouse | Trigger |
|-------------|----------|-----------|---------|
| dev | SSOM_COCO_DB | COMPUTE_WH | Manual |
| qa | SSOM_COCO_DB_QA | COMPUTE_WH | Push to `release/*` |
| preprod | SSOM_COCO_DB_PREPROD | COMPUTE_WH | Push to `main` |
| prod | SSOM_COCO_DB_PROD | COMPUTE_WH | Tag `v*` |

### Environment Variable Overrides

All scripts respect these environment variables (with defaults shown):

```bash
SNOWFLAKE_ACCOUNT=<your_account>
SNOWFLAKE_USER=<your_user>
SNOWFLAKE_PRIVATE_KEY_PATH=~/.snowflake/ci_key.p8
SNOWFLAKE_ROLE=SYSADMIN
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
```

Example override:
```bash
SNOWFLAKE_WAREHOUSE=LARGE_WH bash scripts/deploy_schemachange.sh --env=dev
```

---

## Scripts Reference

All scripts are located in the `scripts/` directory. Run from the project root.

### Initial Deployment

```bash
# Deploy all migrations to dev (first run creates the change history table automatically)
bash scripts/deploy_schemachange.sh --env=dev
```

### Environment-Aware Deployment (CI/CD)

```bash
# Deploy to a specific environment
bash scripts/deploy_schemachange.sh --env=dev
bash scripts/deploy_schemachange.sh --env=qa
bash scripts/deploy_schemachange.sh --env=preprod
bash scripts/deploy_schemachange.sh --env=prod

# Dry-run (shows what would be deployed without executing)
bash scripts/deploy_schemachange.sh --env=prod --dry-run
```

### Data Loading

```bash
# Historical load (full reset + initial data)
bash scripts/run_historical.sh                  # CSV source (default)
bash scripts/run_historical.sh --source=iceberg # Iceberg/Parquet source

# Incremental load (requires historical load first)
bash scripts/run_incremental.sh                  # CSV source (default)
bash scripts/run_incremental.sh --source=iceberg # Iceberg/Parquet source
```

### Testing

```bash
# Smoke tests (schema/object existence checks)
bash scripts/run_smoke_tests.sh --env=dev

# Integration tests (object counts, procedure verification, policy checks)
# Executed via CI workflows after smoke tests pass
```

### Teardown

```bash
# Preview what will be dropped (dry-run)
bash scripts/drop_objects.sh

# Actually drop all objects (DESTRUCTIVE - cannot be undone)
bash scripts/drop_objects.sh --confirm
```

### Rollback

```bash
# Rollback to a previous version (preprod/prod only)
bash scripts/rollback.sh --env=preprod --version=v1.2.0
bash scripts/rollback.sh --env=prod --version=abc123f
```

### Streamlit Dashboard

```bash
# Start the analytics dashboard
bash scripts/streamlit_start.sh

# Stop the dashboard
bash scripts/streamlit_stop.sh
```

---

## CI/CD Pipeline

### Workflow Triggers

| Workflow | Trigger | File |
|----------|---------|------|
| CI Lint & Validate | PR to `develop`, `release/*`, `main` | `.github/workflows/ci.yml` |
| Deploy to QA | Push to `release/*` | `.github/workflows/deploy-qa.yml` |
| Deploy to Pre-PROD | Push to `main` | `.github/workflows/deploy-preprod.yml` |
| Deploy to PROD | Tag `v*` or manual dispatch | `.github/workflows/deploy-prod.yml` |

### CI Pipeline Steps

1. **SQL Lint** — `sqlfluff lint banking/` with Snowflake dialect
2. **Script Validation** — Verifies migration scripts exist with proper naming (V/R/A prefixes) and `environments.yml` structure

### Deployment Pipeline Steps

1. **Deploy** — Runs `deploy_schemachange.sh` for the target environment (applies only unapplied migrations)
2. **Smoke Tests** — Validates all objects were created
3. **Integration/Regression Tests** — Validates object counts, procedures, policies

### Production Rollback (Manual)

Trigger via GitHub Actions UI:
```
gh workflow run deploy-prod.yml -f action=rollback -f rollback_version=<tag-or-sha>
```

---

## Schemachange Migrations

All migrations live in `banking/` and are managed by [schemachange](https://github.com/Snowflake-Labs/schemachange). Schemachange recursively discovers scripts in subdirectories and executes them based on version order.

### Script Types

| Prefix | Behavior | Example |
|--------|----------|---------|
| `V` | Versioned — runs exactly once, in version order | `V1.2.0__silver_tables.sql` |
| `R` | Repeatable — re-runs whenever file content changes (checksum) | `R__gold_views.sql` |
| `A` | Always — runs on every deployment | `A__grants.sql` |

### Migration Inventory

| Version | Location | Objects Created |
|---------|----------|----------------|
| V1.0.0 | `_platform/` | BRONZE, SILVER, GOLD, GOVERNANCE, METADATA schemas |
| V1.1.0 | `bronze/retail/` | T_Customer, T_Account, T_Transaction |
| V1.2.0 | `silver/retail/` | DimCustomer, DimAccount, DimTransactionType, DimDate |
| V1.3.0 | `gold/retail/` | FactDailyTransaction, FactDailyAgg |
| V1.4.0 | `governance/` | Masking policies (NAME, EMAIL, PHONE, LOCATION, FINANCIAL_ID, AMOUNT) |
| V1.5.0 | `governance/` | DATA_QUALITY_LOG table |
| R__ | `silver/retail/` | SCD-2 (Customer), SCD-1 (Account), dimension loaders |
| R__ | `gold/retail/` | Fact table loaders, aggregation procedures |
| R__ | `gold/retail/` | MonthlySpendProfile, TxnTypeTrend views |
| R__ | `orchestration/` | Daily_ETL_Run() master orchestrator |
| R__ | `orchestration/` | TASK_LOAD_CUSTOMER, TASK_LOAD_ACCOUNT, TASK_LOAD_TRANSACTION |
| R__ | `reference/` | CSV_FORMAT, DATA_STAGE, STREAM_DATA_FILES |
| R__ | `reference/` | PARQUET_FORMAT, ICEBERG_STAGE |
| R__ | `governance/` | Masking policy definitions & column assignments |
| R__ | `governance/` | Cleanse_Bronze_Data(), Run_Data_Quality_Checks() |
| A__ | `governance/` | Schema grants and future privileges |

### Change History Table

Schemachange tracks applied migrations in `<DATABASE>.METADATA.SCHEMACHANGE_HISTORY`. This table is auto-created on first deploy (`--create-change-history-table`).

### Adding a New Migration

1. Create a new file in the appropriate `banking/` subdirectory:
   ```
   banking/silver/retail/V1.11.0__add_customer_segment.sql
   ```

2. Use Jinja variables for environment portability:
   ```sql
   USE DATABASE {{ database }};
   ALTER TABLE SILVER.DIMCUSTOMER ADD COLUMN SEGMENT VARCHAR(50);
   ```

3. Test locally with dry-run:
   ```bash
   bash scripts/deploy_schemachange.sh --env=dev --dry-run
   ```

4. Apply:
   ```bash
   bash scripts/deploy_schemachange.sh --env=dev
   ```

5. Commit and push — CI/CD handles QA/preprod/prod automatically.

### Configuration

- **Config file**: `schemachange-config.yml` (root-folder, default vars, change history table)
- **Deploy script**: `scripts/deploy_schemachange.sh` (environment-aware wrapper)
- **Dependencies**: `requirements.txt` (schemachange, pyyaml, jinja2)

### Jinja Variables Available in Migrations

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `{{ database }}` | Target database name | `SSOM_COCO_DB` |
| `{{ warehouse }}` | Compute warehouse | `COMPUTE_WH` |
| `{{ role }}` | Deployment role | `SYSADMIN` |
| `{{ environment }}` | Environment name | `dev` |

---

## Data Flow

```
Source Files (CSV/Parquet)
    │
    ▼
BRONZE (Raw Landing)
    │  T_Customer, T_Account, T_Transaction
    │  Loaded via: Stage → Stream → Tasks (CSV) or COPY INTO (Parquet)
    │
    ▼
SILVER (Conformed Dimensions)
    │  DimCustomer (SCD-2), DimAccount (SCD-1)
    │  DimTransactionType, DimDate
    │
    ▼
GOLD (Business Facts)
       FactDailyTransaction, FactDailyAgg
       Views: MonthlySpendProfile, TxnTypeTrend
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Nonexistent warehouse` | Warehouse not created in target account | Set `SNOWFLAKE_WAREHOUSE` env var to an existing warehouse |
| `JWT token is invalid` | Public key not registered with user | Run `ALTER USER <user> SET RSA_PUBLIC_KEY='...'` in Snowflake |
| `404 Not Found: post <account>.snowflakecomputing.com` | Wrong account identifier format | Use full format: `ORGNAME-ACCOUNTNAME` (e.g., `KXAXARZ-GW22129`) |
| `Connection default is not configured` | Missing `-c` flag or connection not in toml | Ensure `~/.snowflake/connections.toml` has the connection section |
| `Schema does not exist` | Database not created yet | Run `deploy.sh` for the target environment first |

---

## Adding a New Environment

1. Add entry to `environments.yml`:
   ```yaml
   staging:
     database: SSOM_COCO_DB_STAGING
     warehouse: COMPUTE_WH
     connection: MY_TRIAL_ACCOUNT
   ```

2. Create the database in Snowflake:
   ```sql
   CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB_STAGING;
   ```

3. Deploy (schemachange will create the change history table and apply all migrations):
   ```bash
   bash scripts/deploy_schemachange.sh --env=staging
   ```

---

## Key-Pair Authentication Setup

1. Generate RSA key pair:
   ```bash
   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/trial_key.p8 -nocrypt
   openssl rsa -in ~/.snowflake/trial_key.p8 -pubout -out ~/.snowflake/trial_key.pub
   chmod 600 ~/.snowflake/trial_key.p8
   ```

2. Register public key in Snowflake:
   ```sql
   ALTER USER SOMSUJAY SET RSA_PUBLIC_KEY='<paste public key without headers>';
   ```

3. Configure `~/.snowflake/connections.toml`:
   ```toml
   [MY_TRIAL_ACCOUNT]
   account = "KXAXARZ-GW22129"
   user = "SOMSUJAY"
   authenticator = "SNOWFLAKE_JWT"
   private_key_path = "/path/to/.snowflake/trial_key.p8"
   warehouse = "COMPUTE_WH"
   database = "SSOM_COCO_DB"
   ```

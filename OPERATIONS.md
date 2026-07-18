# Operations Guide

## Overview

This project deploys a Teradata-to-Snowflake migration pipeline with a Bronze/Silver/Gold medallion architecture. All scripts are parameterized via environment variables with sensible defaults.

---

## Prerequisites

### Local Development

1. **Snowflake CLI** (`snow`): `pip install snowflake-cli-labs`
2. **Connection config**: `~/.snowflake/connections.toml` must contain a `[MY_TRIAL_ACCOUNT]` section
3. **Key-pair auth**: RSA private key at the path specified in `connections.toml`

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
SNOWFLAKE_CONNECTION=MY_TRIAL_ACCOUNT
SNOWFLAKE_DATABASE=SSOM_COCO_DB
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
```

Example override:
```bash
SNOWFLAKE_WAREHOUSE=LARGE_WH bash scripts/create_objects.sh
```

---

## Scripts Reference

All scripts are located in the `scripts/` directory. Run from the project root.

### Initial Deployment

```bash
# Deploy all SQL objects (schemas, tables, procedures, policies)
bash scripts/create_objects.sh
```

### Environment-Aware Deployment (CI/CD)

```bash
# Deploy to a specific environment
bash scripts/deploy.sh --env=dev
bash scripts/deploy.sh --env=qa
bash scripts/deploy.sh --env=preprod
bash scripts/deploy.sh --env=prod

# Dry-run (shows what would be deployed without executing)
bash scripts/deploy.sh --env=prod --dry-run
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

1. **SQL Lint** — `sqlfluff lint` with Snowflake dialect
2. **Script Validation** — Verifies SQL files exist and `environments.yml` structure

### Deployment Pipeline Steps

1. **Deploy** — Runs `deploy.sh` for the target environment
2. **Smoke Tests** — Validates all objects were created
3. **Integration/Regression Tests** — Validates object counts, procedures, policies

### Production Rollback (Manual)

Trigger via GitHub Actions UI:
```
gh workflow run deploy-prod.yml -f action=rollback -f rollback_version=<tag-or-sha>
```

---

## SQL Scripts Deployment Order

Scripts are deployed sequentially (01-11):

| # | File | Objects Created |
|---|------|----------------|
| 01 | `01_setup_schemas.sql` | BRONZE, SILVER, GOLD, GOVERNANCE schemas |
| 02 | `02_bronze_tables.sql` | T_Customer, T_Account, T_Transaction, stage, stream, tasks |
| 03 | `03_silver_tables.sql` | DimCustomer, DimAccount, DimTransactionType, DimDate |
| 04 | `04_gold_tables.sql` | FactDailyTransaction, FactDailyAgg, views |
| 05 | `05_silver_procedures.sql` | SCD-2 (Customer), SCD-1 (Account), dimension loaders |
| 06 | `06_gold_procedures.sql` | Fact table loaders, aggregation procedures |
| 07 | `07_orchestration.sql` | Daily_ETL_Run() master orchestrator |
| 08 | `08_seed_data.sql` | File formats, stages, streams, load tasks |
| 09 | `09_masking_policies.sql` | MASK_NAME, MASK_EMAIL, MASK_PHONE, MASK_LOCATION, MASK_FINANCIAL_ID, MASK_AMOUNT |
| 10 | `10_data_quality.sql` | DATA_QUALITY_LOG table, Cleanse_Bronze_Data(), Run_Data_Quality_Checks() |
| 11 | `11_iceberg_objects.sql` | PARQUET_FORMAT, ICEBERG_STAGE |

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

3. Deploy:
   ```bash
   bash scripts/deploy.sh --env=staging
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

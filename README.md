# Teradata to Snowflake Migration

Converts a Teradata DWH ETL pipeline into Snowflake using a **Medallion Architecture** (Bronze / Silver / Gold) with two ingestion options: CSV files or Iceberg/Parquet files. Deployments are managed via **schemachange** with CI/CD through GitHub Actions.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Source Data                                            │
│  ┌───────────────┐        ┌───────────────────────┐    │
│  │  CSV Files    │        │  Iceberg/Parquet Files │    │
│  │  (sample_data │        │  (iceberg_warehouse/)  │    │
│  │   _file/)     │        │                        │    │
│  └───────┬───────┘        └───────────┬───────────┘    │
└──────────┼────────────────────────────┼────────────────┘
           │                            │
           ▼                            ▼
┌──────────────────┐       ┌────────────────────────┐
│ @BRONZE.DATA_    │       │ @BRONZE.ICEBERG_STAGE  │
│  STAGE (CSV)     │       │   (Parquet)            │
│  + Tasks + Stream│       │   + COPY INTO          │
└────────┬─────────┘       └───────────┬────────────┘
         │                             │
         └──────────────┬──────────────┘
                        ▼
              ┌─────────────────┐
              │   BRONZE Layer  │  Raw staging tables
              │   T_Customer    │
              │   T_Account     │
              │   T_Transaction │
              └────────┬────────┘
                       ▼
              ┌─────────────────┐
              │   SILVER Layer  │  Cleansed dimensions
              │   DimCustomer   │  (SCD-2)
              │   DimAccount    │  (SCD-1)
              │   DimTxnType    │
              │   DimDate       │
              └────────┬────────┘
                       ▼
              ┌─────────────────┐
              │   GOLD Layer    │  Business-ready facts
              │   FactDaily     │
              │   Transaction   │
              │   FactDailyAgg  │
              └─────────────────┘
```

## Prerequisites

- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli) (`snow`) installed and configured
- Connection `MY_TRIAL_ACCOUNT` configured in `~/.snowflake/connections.toml`
- Python 3.11+ (for schemachange, Iceberg table creation, and Streamlit dashboard)
- [schemachange](https://github.com/Snowflake-Labs/schemachange) (`pip install schemachange`)
- [sqlfluff](https://sqlfluff.com/) (`pip install sqlfluff`) for SQL linting

## Quick Start

### 1. Deploy Snowflake Objects (via Schemachange)

```bash
# Set required environment variables
export SNOWFLAKE_ACCOUNT=KXAXARZ-GW22129
export SNOWFLAKE_USER=SOMSUJAY

# Deploy to dev
bash scripts/deploy_schemachange.sh --env=dev

# Dry-run (see what would be deployed without executing)
bash scripts/deploy_schemachange.sh --env=dev --dry-run
```

### 2. Run Smoke Tests

```bash
bash scripts/run_smoke_tests.sh --env=dev
```

### 3. Run the ETL Pipeline

**Option A: CSV Source (default)**

```bash
bash scripts/run_historical.sh --source=csv
bash scripts/run_incremental.sh --source=csv
```

**Option B: Iceberg/Parquet Source**

First generate the local Iceberg tables (if not already present):

```bash
pip install pyiceberg pyarrow
python scripts/create_iceberg_tables.py
```

Then run the pipeline from Parquet:

```bash
bash scripts/run_historical.sh --source=iceberg
bash scripts/run_incremental.sh --source=iceberg
```

**End-to-End (historical + incremental + dashboard)**

```bash
bash scripts/run_etl_end_to_end.sh                  # CSV (default)
bash scripts/run_etl_end_to_end.sh --source=iceberg # Iceberg/Parquet
```

### 4. Launch Dashboard

```bash
bash scripts/streamlit_start.sh
# Dashboard available at http://localhost:8501

bash scripts/streamlit_stop.sh
```

### 5. Tear Down

```bash
bash scripts/drop_objects.sh           # dry-run (shows what will be dropped)
bash scripts/drop_objects.sh --confirm # actually drops everything
```

## Project Structure

```
├── banking/                       # Schemachange migration root
│   ├── _platform/
│   │   └── V1.0.0__setup_schemas.sql
│   ├── bronze/retail/
│   │   └── V1.1.0__bronze_tables.sql
│   ├── silver/retail/
│   │   ├── V1.2.0__silver_tables.sql
│   │   └── V1.4.0__silver_procedures.sql
│   ├── gold/retail/
│   │   ├── V1.3.0__gold_tables.sql
│   │   ├── V1.5.0__gold_procedures.sql
│   │   └── R__gold_views.sql
│   ├── orchestration/
│   │   ├── V1.6.0__orchestration.sql
│   │   └── V1.7.1__ingestion_tasks.sql
│   ├── reference/
│   │   ├── V1.7.0__seed_data.sql
│   │   └── V1.10.0__iceberg_objects.sql
│   └── governance/
│       ├── V1.8.0__masking_policies.sql
│       ├── V1.9.0__data_quality.sql
│       └── A__grants.sql
├── scripts/                       # Deployment & ETL automation
│   ├── deploy_schemachange.sh     # Primary deployer (schemachange)
│   ├── deploy.sh                  # Legacy deployer
│   ├── rollback.sh
│   ├── run_smoke_tests.sh
│   ├── run_historical.sh
│   ├── run_incremental.sh
│   ├── run_etl_end_to_end.sh
│   ├── create_objects.sh
│   ├── drop_objects.sh
│   ├── create_iceberg_tables.py
│   ├── streamlit_start.sh
│   └── streamlit_stop.sh
├── tests/
│   ├── smoke_test.sql             # Post-deploy object checks
│   └── integration_test.sql       # Deep validation
├── .github/workflows/             # CI/CD pipelines
│   ├── ci.yml                     # Lint + validate on PRs
│   ├── deploy-qa.yml              # Deploy on push to release/*
│   ├── deploy-preprod.yml         # Deploy on push to main
│   └── deploy-prod.yml            # Deploy on tag v* or manual
├── Teradata_Scripts/              # Original Teradata source SQL
├── sample_data_file/              # CSV source data (history + incremental)
├── iceberg_warehouse/             # Local Iceberg tables (Parquet + metadata)
├── streamlit_app/                 # Multi-page Streamlit dashboard
├── config/                        # Snowflake Git integration config
├── environments.yml               # Environment config (dev/qa/preprod/prod)
├── schemachange-config.yml        # Schemachange settings
├── .sqlfluff                      # SQL lint rules
└── DEVOPS_MANUAL.md               # Full operations manual
```

## CI/CD Pipeline

| Workflow | Trigger | Action |
|----------|---------|--------|
| `ci.yml` | PR to `develop`, `release/*`, `main` | sqlfluff lint + script validation |
| `deploy-qa.yml` | Push to `release/*` | Deploy to QA via schemachange |
| `deploy-preprod.yml` | Push to `main` | Deploy to PreProd via schemachange |
| `deploy-prod.yml` | Tag `v*` or manual dispatch | Deploy to Prod via schemachange |

**Branching strategy:** `feature/*` → `develop` → `release/*` → `main` → tag `v*`

## Environments

| Environment | Database | Trigger |
|-------------|----------|---------|
| dev | `SSOM_COCO_DB` | Manual (local) |
| qa | `SSOM_COCO_DB_QA` | Push to `release/*` |
| preprod | `SSOM_COCO_DB_PREPROD` | Push to `main` |
| prod | `SSOM_COCO_DB_PROD` | Tag `v*` |

## Schemachange Conventions

| Prefix | Meaning | Behavior |
|--------|---------|----------|
| `V<ver>__<name>.sql` | Versioned | Runs once, tracked in change history |
| `R__<name>.sql` | Repeatable | Re-runs when file content changes |
| `A__<name>.sql` | Always-run | Runs on every deployment |

Template variables available in SQL: `{{ database }}`, `{{ warehouse }}`, `{{ role }}`, `{{ environment }}`

## Ingestion Options

| Option | Flag | Source Files | Mechanism |
|--------|------|--------------|-----------|
| **CSV** | `--source=csv` | `sample_data_file/*.csv` | PUT → Named Stage → Directory Stream → Tasks (COPY INTO) |
| **Iceberg** | `--source=iceberg` | `iceberg_warehouse/**/*.parquet` | PUT Parquet → Internal Stage → COPY INTO with column transforms |

Both options load into the same Bronze tables. Downstream ETL (Silver/Gold), data quality checks, and masking policies are identical regardless of source.

## Snowflake Target

| Setting | Value |
|---------|-------|
| Account | `KXAXARZ-GW22129` |
| Connection | `MY_TRIAL_ACCOUNT` |
| Warehouse | `COMPUTE_WH` |
| Schemas | `BRONZE`, `SILVER`, `GOLD`, `GOVERNANCE`, `METADATA` |

## Sample Data

| Entity | History Rows | Incremental Rows | Description |
|--------|-------------|------------------|-------------|
| Customer | 20 | 10 (5 updates + 5 new) | Customer master data |
| Account | 35 | 13 | Account records |
| Transaction | 101 | 31 | Financial transactions |

## Documentation

- [`DEVOPS_MANUAL.md`](DEVOPS_MANUAL.md) — Full operations manual (deployment, rollback, secrets, incident response)
- [`OPERATIONS.md`](OPERATIONS.md) — Operational runbooks
- [`lineage.md`](lineage.md) — Data lineage documentation

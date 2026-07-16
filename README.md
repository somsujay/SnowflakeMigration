# Teradata to Snowflake Migration

Converts a Teradata DWH ETL pipeline into Snowflake using a **Medallion Architecture** (Bronze / Silver / Gold) with two ingestion options: CSV files or Iceberg/Parquet files.

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
- Connection `HAKKODAINC_PARTNER` configured in `~/.snowflake/connections.toml`
- Python 3.9+ (for Iceberg table creation and Streamlit dashboard)

## Quick Start

### 0. Drop Existing Objects (if re-deploying)

```bash
bash scripts/drop_objects.sh           # dry-run (shows what will be dropped)
bash scripts/drop_objects.sh --confirm # actually drops everything
```

### 1. Deploy Snowflake Objects

```bash
bash scripts/create_objects.sh
```

Deploys all schemas, tables, stages, tasks, procedures, masking policies, and data quality framework.

### 2. Run the ETL Pipeline

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

### 3. Launch Dashboard

```bash
bash scripts/streamlit_start.sh
```

Dashboard available at http://localhost:8501

### 4. Tear Down

```bash
bash scripts/drop_objects.sh           # dry-run (shows what will be dropped)
bash scripts/drop_objects.sh --confirm # actually drops everything
```

## Ingestion Options

| Option | Flag | Source Files | Mechanism |
|--------|------|--------------|-----------|
| **CSV** | `--source=csv` | `sample_data_file/*.csv` | PUT → Named Stage → Directory Stream → Tasks (COPY INTO) |
| **Iceberg** | `--source=iceberg` | `iceberg_warehouse/**/*.parquet` | PUT Parquet → Internal Stage → COPY INTO with column transforms |

Both options load into the same Bronze tables. Downstream ETL (Silver/Gold), data quality checks, and masking policies are identical regardless of source.

## Project Structure

```
├── Teradata_Scripts/          # Original Teradata source SQL
├── Snowflake_Scripts/         # Converted Snowflake SQL (01-11)
│   ├── 01_setup_schemas.sql
│   ├── 02_bronze_tables.sql
│   ├── 03_silver_tables.sql
│   ├── 04_gold_tables.sql
│   ├── 05_silver_procedures.sql
│   ├── 06_gold_procedures.sql
│   ├── 07_orchestration.sql
│   ├── 08_seed_data.sql       # CSV stage, stream, tasks
│   ├── 09_masking_policies.sql
│   ├── 10_data_quality.sql
│   └── 11_iceberg_objects.sql # Parquet stage + file format
├── sample_data_file/          # CSV source data (history + incremental)
├── iceberg_warehouse/         # Local Iceberg tables (Parquet + metadata)
├── scripts/                   # Shell automation
│   ├── create_objects.sh
│   ├── drop_objects.sh
│   ├── run_historical.sh
│   ├── run_incremental.sh
│   ├── run_etl_end_to_end.sh
│   ├── create_iceberg_tables.py
│   ├── streamlit_start.sh
│   └── streamlit_stop.sh
├── streamlit_app/             # Multi-page Streamlit dashboard
└── config/                    # Snowflake Git integration config
```

## Snowflake Target

| Setting | Value |
|---------|-------|
| Connection | `HAKKODAINC_PARTNER` |
| Database | `SSOM_COCO_DB` |
| Warehouse | `SSOM_COCO_WH` |
| Schemas | `BRONZE`, `SILVER`, `GOLD`, `GOVERNANCE` |

## Sample Data

| Entity | History Rows | Incremental Rows | Description |
|--------|-------------|------------------|-------------|
| Customer | 20 | 10 (5 updates + 5 new) | Customer master data |
| Account | 35 | 13 | Account records |
| Transaction | 101 | 31 | Financial transactions |

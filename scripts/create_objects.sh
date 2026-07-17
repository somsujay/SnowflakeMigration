#!/bin/bash
# ============================================================
# create_objects.sh
# Deploy all Snowflake objects by running SQL scripts 01–10
# Test
# Executes in order:
#   01_setup_schemas.sql       → Schemas
#   02_bronze_tables.sql       → Bronze tables + stage + stream + tasks
#   03_silver_tables.sql       → Silver dimension tables
#   04_gold_tables.sql         → Gold fact tables + views
#   05_silver_procedures.sql   → Silver ETL procedures
#   06_gold_procedures.sql     → Gold ETL procedures
#   07_orchestration.sql       → Daily_ETL_Run() orchestrator
#   08_seed_data.sql           → Seed/reference data
#   09_masking_policies.sql    → Governance masking policies
#   10_data_quality.sql        → DQ framework (table + procedures)
# ============================================================

set -e

# --- Configuration ---
CONN="${SNOWFLAKE_CONNECTION:-MY_TRIAL_ACCOUNT}"
DB="${SNOWFLAKE_DATABASE:-SSOM_COCO_DB}"
WH="${SNOWFLAKE_WAREHOUSE:-COMPUTE_WH}"

# Resolve project root (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SQL_DIR="${PROJECT_DIR}/Snowflake_Scripts"

# --- Helper Functions ---
header() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
    echo ""
}

run_sql_file() {
    local file="$1"
    local desc="$2"
    echo ">> Deploying: $(basename "$file") — ${desc}"
    snow sql -c "$CONN" --database "$DB" --warehouse "$WH" -f "$file"
    echo "   [OK]"
    echo ""
}

# ============================================================
# PRE-CHECK
# ============================================================
header "CREATE ALL SNOWFLAKE OBJECTS"

echo "Connection: ${CONN}"
echo "Database:   ${DB}"
echo "Warehouse:  ${WH}"
echo "SQL Dir:    ${SQL_DIR}"
echo ""

# Verify SQL directory exists
if [ ! -d "$SQL_DIR" ]; then
    echo "ERROR: SQL directory not found at ${SQL_DIR}"
    exit 1
fi

# Each run_sql_file call sets its own context via stdin piping
echo ""

# ============================================================
# DEPLOY SCRIPTS IN ORDER
# ============================================================

run_sql_file "${SQL_DIR}/01_setup_schemas.sql" \
    "Schemas (BRONZE, SILVER, GOLD)"

run_sql_file "${SQL_DIR}/02_bronze_tables.sql" \
    "Bronze tables, stage, stream, tasks"

run_sql_file "${SQL_DIR}/03_silver_tables.sql" \
    "Silver dimension tables"

run_sql_file "${SQL_DIR}/04_gold_tables.sql" \
    "Gold fact tables and views"

run_sql_file "${SQL_DIR}/05_silver_procedures.sql" \
    "Silver ETL procedures (SCD-2, SCD-1)"

run_sql_file "${SQL_DIR}/06_gold_procedures.sql" \
    "Gold ETL procedures"

run_sql_file "${SQL_DIR}/07_orchestration.sql" \
    "Daily_ETL_Run() orchestrator"

run_sql_file "${SQL_DIR}/08_seed_data.sql" \
    "Seed/reference data"

run_sql_file "${SQL_DIR}/09_masking_policies.sql" \
    "Governance masking policies"

run_sql_file "${SQL_DIR}/10_data_quality.sql" \
    "Data quality framework"

run_sql_file "${SQL_DIR}/11_iceberg_objects.sql" \
    "Iceberg/Parquet ingestion objects"

# ============================================================
# SUMMARY
# ============================================================
header "ALL OBJECTS CREATED SUCCESSFULLY"
echo "Deployed 11 SQL scripts to ${DB}."
echo ""
echo "Objects created:"
echo "  Schemas:    BRONZE, SILVER, GOLD, GOVERNANCE"
echo "  Tables:     T_Customer, T_Account, T_Transaction,"
echo "              DimCustomer, DimAccount, DimTransactionType, DimDate,"
echo "              FactDailyTransaction, FactDailyAgg, DATA_QUALITY_LOG"
echo "  Views:      MonthlySpendProfile, TxnTypeTrend"
echo "  Stages:     BRONZE.DATA_STAGE (CSV), BRONZE.ICEBERG_STAGE (Parquet)"
echo "  Formats:    BRONZE.CSV_FORMAT, BRONZE.PARQUET_FORMAT"
echo "  Stream:     BRONZE.STREAM_DATA_FILES"
echo "  Tasks:      TASK_LOAD_CUSTOMER, TASK_LOAD_ACCOUNT, TASK_LOAD_TRANSACTION"
echo "  Procedures: Close_Current_DimCustomer_Record, Insert_New_DimCustomer_Record,"
echo "              Load_DimAccount_SCD1, Load_DimTransactionType, Populate_DimDate,"
echo "              Load_FactDailyTransaction, Load_FactDailyAgg, Daily_ETL_Run,"
echo "              Cleanse_Bronze_Data, Run_Data_Quality_Checks"
echo "  Policies:   MASK_NAME, MASK_EMAIL, MASK_PHONE, MASK_LOCATION,"
echo "              MASK_FINANCIAL_ID, MASK_AMOUNT"
echo ""
echo "Next steps:"
echo "  bash scripts/run_historical.sh                  # Load history (CSV, default)"
echo "  bash scripts/run_historical.sh --source=iceberg # Load history (Iceberg/Parquet)"
echo "  bash scripts/run_incremental.sh                 # Load incremental (CSV)"
echo "  bash scripts/run_incremental.sh --source=iceberg # Load incremental (Iceberg)"
echo "  bash scripts/streamlit_start.sh                 # Start dashboard"
echo ""

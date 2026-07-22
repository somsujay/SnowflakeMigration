#!/bin/bash
# ============================================================
# run_incremental.sh
# Load incremental data + Run ETL + Validate
#
# Prerequisites: run_historical.sh must have been run first
#
# Usage:
#   bash run_incremental.sh                 # Default: CSV source
#   bash run_incremental.sh --source=csv    # Explicit: CSV source
#   bash run_incremental.sh --source=iceberg # Iceberg/Parquet source
#
# Flow:
#   1. Incremental Load:
#      - CSV:     PUT incremental CSVs → REFRESH → EXECUTE TASKs
#      - Iceberg: PUT Parquet files → COPY INTO from Parquet
#   2. Data Cleansing & Validation
#   3. ETL (CALL Daily_ETL_Run())
#   4. Post-ETL Verification & Validation
# ============================================================

set -e

# --- Configuration ---
CONN="${SNOWFLAKE_CONNECTION:-MY_TRIAL_ACCOUNT}"
DB="${SNOWFLAKE_DATABASE:-SSOM_COCO_DB}"
WH="${SNOWFLAKE_WAREHOUSE:-COMPUTE_WH}"

# Resolve project root (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${PROJECT_DIR}/sample_data_file"
ICEBERG_DIR="${PROJECT_DIR}/iceberg_warehouse/teradata_migration"

# Wait time (seconds) after EXECUTE TASK for async completion
TASK_WAIT=15

# --- Parse Arguments ---
SOURCE="csv"
for arg in "$@"; do
    case $arg in
        --source=*)
            SOURCE="${arg#*=}"
            shift
            ;;
    esac
done

if [[ "$SOURCE" != "csv" && "$SOURCE" != "iceberg" ]]; then
    echo "ERROR: Invalid --source value '${SOURCE}'. Must be 'csv' or 'iceberg'."
    exit 1
fi

# --- Helper Functions ---
run_sql() {
    snow sql -c "$CONN" -q "USE DATABASE ${DB}; USE WAREHOUSE ${WH}; $1"
}

header() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
    echo ""
}

# ============================================================
# Phase 1: INCREMENTAL LOAD
# ============================================================
if [ "$SOURCE" = "csv" ]; then
    # ----------------------------------------------------------
    # Option A: CSV Source (PUT → Named Stage → COPY INTO via Tasks)
    # ----------------------------------------------------------
    header "Phase 1: INCREMENTAL LOAD (CSV) - Upload incremental CSVs and load into Bronze"

    echo ">> Uploading incremental CSV files to stage..."
    run_sql "PUT file://${DATA_DIR}/T_Customer_incremental.csv @BRONZE.DATA_STAGE/customer/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"
    run_sql "PUT file://${DATA_DIR}/T_Account_incremental.csv @BRONZE.DATA_STAGE/account/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"
    run_sql "PUT file://${DATA_DIR}/T_Transaction_incremental.csv @BRONZE.DATA_STAGE/transaction/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"

    echo ">> Refreshing stage directory table..."
    run_sql "ALTER STAGE BRONZE.DATA_STAGE REFRESH;"

    echo ">> Executing load tasks..."
    run_sql "EXECUTE TASK BRONZE.TASK_LOAD_CUSTOMER;"
    run_sql "EXECUTE TASK BRONZE.TASK_LOAD_ACCOUNT;"
    run_sql "EXECUTE TASK BRONZE.TASK_LOAD_TRANSACTION;"

    echo ">> Waiting ${TASK_WAIT}s for tasks to complete..."
    sleep "$TASK_WAIT"

else
    # ----------------------------------------------------------
    # Option B: Iceberg/Parquet Source (PUT Parquet → COPY INTO)
    # ----------------------------------------------------------
    header "Phase 1: INCREMENTAL LOAD (ICEBERG) - Upload Parquet files and load into Bronze"

    # Find the second Parquet file per entity (incremental snapshot)
    # The Iceberg tables have 2 data files: first = history, second = incremental
    CUST_PARQUETS=($(ls "${ICEBERG_DIR}/t_customer/data/"*.parquet 2>/dev/null | sort))
    ACCT_PARQUETS=($(ls "${ICEBERG_DIR}/t_account/data/"*.parquet 2>/dev/null | sort))
    TXN_PARQUETS=($(ls "${ICEBERG_DIR}/t_transaction/data/"*.parquet 2>/dev/null | sort))

    CUST_PARQUET="${CUST_PARQUETS[1]}"
    ACCT_PARQUET="${ACCT_PARQUETS[1]}"
    TXN_PARQUET="${TXN_PARQUETS[1]}"

    if [[ -z "$CUST_PARQUET" || -z "$ACCT_PARQUET" || -z "$TXN_PARQUET" ]]; then
        echo "ERROR: Incremental Parquet files not found in ${ICEBERG_DIR}."
        echo "Run 'python scripts/create_iceberg_tables.py' first to generate Iceberg tables."
        echo "Ensure both history and incremental CSVs were loaded to produce 2 snapshots."
        exit 1
    fi

    echo ">> Uploading incremental Parquet files to Iceberg stage..."
    run_sql "PUT file://${CUST_PARQUET} @BRONZE.ICEBERG_STAGE/customer/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"
    run_sql "PUT file://${ACCT_PARQUET} @BRONZE.ICEBERG_STAGE/account/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"
    run_sql "PUT file://${TXN_PARQUET} @BRONZE.ICEBERG_STAGE/transaction/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;"

    echo ">> Loading T_Customer from Parquet..."
    run_sql "COPY INTO BRONZE.T_Customer (Customer_ID, First_Name, Last_Name, Email_Address, Phone_Number, City, State_Province, Country, Created_Timestamp)
    FROM (SELECT \$1:Customer_ID::VARCHAR, \$1:First_Name::VARCHAR, \$1:Last_Name::VARCHAR, \$1:Email_Address::VARCHAR, \$1:Phone_Number::VARCHAR, \$1:City::VARCHAR, \$1:State_Province::VARCHAR, \$1:Country::VARCHAR, TO_TIMESTAMP_NTZ(\$1:Created_Timestamp::NUMBER / 1000000)
          FROM @BRONZE.ICEBERG_STAGE/customer/)
    FILE_FORMAT = (FORMAT_NAME = 'BRONZE.PARQUET_FORMAT');"

    echo ">> Loading T_Account from Parquet..."
    run_sql "COPY INTO BRONZE.T_Account (Account_ID, Customer_ID, Account_Type, Status, Currency_Code, Open_Date, Created_Timestamp)
    FROM (SELECT \$1:Account_ID::VARCHAR, \$1:Customer_ID::VARCHAR, \$1:Account_Type::VARCHAR, \$1:Status::VARCHAR, \$1:Currency_Code::VARCHAR, \$1:Open_Date::DATE, TO_TIMESTAMP_NTZ(\$1:Created_Timestamp::NUMBER / 1000000)
          FROM @BRONZE.ICEBERG_STAGE/account/)
    FILE_FORMAT = (FORMAT_NAME = 'BRONZE.PARQUET_FORMAT');"

    echo ">> Loading T_Transaction from Parquet..."
    run_sql "COPY INTO BRONZE.T_Transaction (Transaction_ID, Account_ID, Transaction_Date, Transaction_Type, Amount, Description)
    FROM (SELECT \$1:Transaction_ID::VARCHAR, \$1:Account_ID::VARCHAR, TO_TIMESTAMP_NTZ(\$1:Transaction_Date::NUMBER / 1000000), \$1:Transaction_Type::VARCHAR, \$1:Amount::DECIMAL(18,2), \$1:Description::VARCHAR
          FROM @BRONZE.ICEBERG_STAGE/transaction/)
    FILE_FORMAT = (FORMAT_NAME = 'BRONZE.PARQUET_FORMAT');"

fi

echo ">> Verifying Bronze row counts (expected: Customer=30, Account=47, Transaction=130)..."
run_sql "SELECT 'T_Customer' AS table_name, COUNT(*) AS row_count FROM BRONZE.T_Customer
         UNION ALL
         SELECT 'T_Account', COUNT(*) FROM BRONZE.T_Account
         UNION ALL
         SELECT 'T_Transaction', COUNT(*) FROM BRONZE.T_Transaction;"

echo "[Phase 1 COMPLETE]"

# ============================================================
# Phase 2: DATA CLEANSING & VALIDATION
# ============================================================
header "Phase 2: DATA CLEANSING & VALIDATION"

echo ">> Running Bronze data cleansing..."
run_sql "CALL GOVERNANCE.Cleanse_Bronze_Data();"

echo ">> Running data quality checks..."
run_sql "CALL GOVERNANCE.Run_Data_Quality_Checks();"

echo ">> Validation summary:"
run_sql "SELECT severity, COUNT(*) AS check_count, SUM(records_failed) AS total_failures
         FROM GOVERNANCE.DATA_QUALITY_LOG
         WHERE run_id = (SELECT MAX(run_id) FROM GOVERNANCE.DATA_QUALITY_LOG)
         GROUP BY severity
         ORDER BY CASE severity WHEN 'ERROR' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END;"

echo "[Phase 2 COMPLETE]"

# ============================================================
# Phase 3: ETL (Bronze → Silver → Gold)
# ============================================================
header "Phase 3: ETL - Re-run Daily_ETL_Run() with incremental data"

run_sql "CALL ${DB}.GOLD.Daily_ETL_Run();"

echo ">> Verifying final Silver/Gold row counts..."
run_sql "SELECT 'DimCustomer' AS table_name, COUNT(*) AS row_count FROM SILVER.DimCustomer
         UNION ALL
         SELECT 'DimAccount', COUNT(*) FROM SILVER.DimAccount
         UNION ALL
         SELECT 'DimTransactionType', COUNT(*) FROM SILVER.DimTransactionType
         UNION ALL
         SELECT 'FactDailyTransaction', COUNT(*) FROM GOLD.FactDailyTransaction
         UNION ALL
         SELECT 'FactDailyAgg', COUNT(*) FROM GOLD.FactDailyAgg;"

echo "[Phase 3 COMPLETE]"

# ============================================================
# Phase 4: POST-ETL VALIDATION
# ============================================================
header "Phase 4: POST-ETL VALIDATION - Cross-layer integrity checks"

echo ">> Running post-ETL data quality checks..."
run_sql "CALL GOVERNANCE.Run_Data_Quality_Checks();"

echo ">> Post-ETL validation summary:"
run_sql "SELECT severity, COUNT(*) AS check_count, SUM(records_failed) AS total_failures
         FROM GOVERNANCE.DATA_QUALITY_LOG
         WHERE run_id = (SELECT MAX(run_id) FROM GOVERNANCE.DATA_QUALITY_LOG)
         GROUP BY severity
         ORDER BY CASE severity WHEN 'ERROR' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END;"

echo ">> Detailed failures (if any):"
run_sql "SELECT check_name, table_name, severity, records_failed, details
         FROM GOVERNANCE.DATA_QUALITY_LOG
         WHERE run_id = (SELECT MAX(run_id) FROM GOVERNANCE.DATA_QUALITY_LOG)
           AND records_failed > 0
         ORDER BY CASE severity WHEN 'ERROR' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END;"

echo "[Phase 4 COMPLETE]"

# ============================================================
# SUMMARY
# ============================================================
header "INCREMENTAL LOAD COMPLETE (source: ${SOURCE})"
echo "Incremental data loaded, cleansed, and validated successfully."
echo "Source: ${SOURCE}"
echo ""
echo "Expected final row counts:"
echo "  Bronze: T_Customer=25, T_Account=44, T_Transaction=130"
echo "  Silver: DimCustomer=60 (SCD-2), DimAccount=47, DimTransactionType=4"
echo "  Gold:   FactDailyTransaction=130, FactDailyAgg=468"
echo ""

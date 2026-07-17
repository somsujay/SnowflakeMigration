#!/bin/bash
# ============================================================
# drop_objects.sh
# Drop ALL Snowflake objects created by this project
#
# WARNING: This is DESTRUCTIVE and IRREVERSIBLE.
# Pass --confirm flag to execute.
#
# Usage:
#   bash scripts/drop_objects.sh           # dry-run (shows what will be dropped)
#   bash scripts/drop_objects.sh --confirm # actually drops everything
# ============================================================

# NOTE: No 'set -e' — individual DROP commands may fail if objects/schemas
# were already removed, and that is expected behavior.

# --- Configuration ---
CONN="MY_TRIAL_ACCOUNT"
DB="SSOM_COCO_DB"
WH="SSOM_COCO_WH"

# --- Safety Check ---
if [ "$1" != "--confirm" ]; then
    echo "============================================================"
    echo "  DROP ALL OBJECTS - DRY RUN"
    echo "============================================================"
    echo ""
    echo "This script will DROP the following objects from ${DB}:"
    echo ""
    echo "  GOLD schema:"
    echo "    - VIEW  MonthlySpendProfile"
    echo "    - VIEW  TxnTypeTrend"
    echo "    - TABLE FactDailyTransaction"
    echo "    - TABLE FactDailyAgg"
    echo ""
    echo "  SILVER schema:"
    echo "    - TABLE DimCustomer"
    echo "    - TABLE DimAccount"
    echo "    - TABLE DimTransactionType"
    echo "    - TABLE DimDate"
    echo ""
    echo "  BRONZE schema:"
    echo "    - TABLE T_Customer"
    echo "    - TABLE T_Account"
    echo "    - TABLE T_Transaction"
    echo "    - TASK  TASK_LOAD_CUSTOMER"
    echo "    - TASK  TASK_LOAD_ACCOUNT"
    echo "    - TASK  TASK_LOAD_TRANSACTION"
    echo "    - STREAM STREAM_DATA_FILES"
    echo "    - STAGE DATA_STAGE (CSV)"
    echo "    - STAGE ICEBERG_STAGE (Parquet)"
    echo "    - FILE FORMAT CSV_FORMAT"
    echo "    - FILE FORMAT PARQUET_FORMAT"
    echo ""
    echo "  GOVERNANCE schema:"
    echo "    - TABLE DATA_QUALITY_LOG"
    echo "    - PROCEDURE Cleanse_Bronze_Data()"
    echo "    - PROCEDURE Run_Data_Quality_Checks()"
    echo "    - MASKING POLICY MASK_NAME, MASK_EMAIL, MASK_PHONE,"
    echo "                     MASK_LOCATION, MASK_FINANCIAL_ID, MASK_AMOUNT"
    echo ""
    echo "  PUBLIC schema:"
    echo "    - PROCEDURE Daily_ETL_Run()"
    echo ""
    echo "  Procedures:"
    echo "    - SILVER.Close_Current_DimCustomer_Record()"
    echo "    - SILVER.Insert_New_DimCustomer_Record()"
    echo "    - SILVER.Load_DimAccount_SCD1()"
    echo "    - SILVER.Load_DimTransactionType()"
    echo "    - SILVER.Populate_DimDate(DATE, DATE)"
    echo "    - GOLD.Load_FactDailyTransaction(DATE)"
    echo "    - GOLD.Load_FactDailyAgg(DATE)"
    echo ""
    echo "  Schemas: BRONZE, SILVER, GOLD, GOVERNANCE"
    echo ""
    echo "============================================================"
    echo "  To execute, run:  bash $0 --confirm"
    echo "============================================================"
    exit 0
fi

# --- Helper ---
run_sql() {
    snow sql -c "$CONN" -q "USE DATABASE ${DB}; USE WAREHOUSE ${WH}; $1" 2>/dev/null || true
}

header() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
    echo ""
}

echo ""
echo "!!! WARNING: DROPPING ALL OBJECTS IN ${DB} !!!"
echo ""

# ============================================================
# Step 1: Suspend and drop tasks
# ============================================================
header "Dropping Tasks"

run_sql "ALTER TASK IF EXISTS BRONZE.TASK_LOAD_CUSTOMER SUSPEND;"
run_sql "ALTER TASK IF EXISTS BRONZE.TASK_LOAD_ACCOUNT SUSPEND;"
run_sql "ALTER TASK IF EXISTS BRONZE.TASK_LOAD_TRANSACTION SUSPEND;"
run_sql "DROP TASK IF EXISTS BRONZE.TASK_LOAD_CUSTOMER;"
run_sql "DROP TASK IF EXISTS BRONZE.TASK_LOAD_ACCOUNT;"
run_sql "DROP TASK IF EXISTS BRONZE.TASK_LOAD_TRANSACTION;"

echo ">> Tasks dropped."

# ============================================================
# Step 2: Drop views
# ============================================================
header "Dropping Views"

run_sql "DROP VIEW IF EXISTS GOLD.MonthlySpendProfile;"
run_sql "DROP VIEW IF EXISTS GOLD.TxnTypeTrend;"

echo ">> Views dropped."

# ============================================================
# Step 3: Drop procedures
# ============================================================
header "Dropping Procedures"

run_sql "DROP PROCEDURE IF EXISTS PUBLIC.Daily_ETL_Run();"
run_sql "DROP PROCEDURE IF EXISTS SILVER.Close_Current_DimCustomer_Record();"
run_sql "DROP PROCEDURE IF EXISTS SILVER.Insert_New_DimCustomer_Record();"
run_sql "DROP PROCEDURE IF EXISTS SILVER.Load_DimAccount_SCD1();"
run_sql "DROP PROCEDURE IF EXISTS SILVER.Load_DimTransactionType();"
run_sql "DROP PROCEDURE IF EXISTS SILVER.Populate_DimDate(DATE, DATE);"
run_sql "DROP PROCEDURE IF EXISTS GOLD.Load_FactDailyTransaction(DATE);"
run_sql "DROP PROCEDURE IF EXISTS GOLD.Load_FactDailyAgg(DATE);"
run_sql "DROP PROCEDURE IF EXISTS GOVERNANCE.Cleanse_Bronze_Data();"
run_sql "DROP PROCEDURE IF EXISTS GOVERNANCE.Run_Data_Quality_Checks();"

echo ">> Procedures dropped."

# ============================================================
# Step 4: Drop tables
# ============================================================
header "Dropping Tables"

run_sql "DROP TABLE IF EXISTS GOLD.FactDailyTransaction;"
run_sql "DROP TABLE IF EXISTS GOLD.FactDailyAgg;"
run_sql "DROP TABLE IF EXISTS SILVER.DimCustomer;"
run_sql "DROP TABLE IF EXISTS SILVER.DimAccount;"
run_sql "DROP TABLE IF EXISTS SILVER.DimTransactionType;"
run_sql "DROP TABLE IF EXISTS SILVER.DimDate;"
run_sql "DROP TABLE IF EXISTS BRONZE.T_Customer;"
run_sql "DROP TABLE IF EXISTS BRONZE.T_Account;"
run_sql "DROP TABLE IF EXISTS BRONZE.T_Transaction;"
run_sql "DROP TABLE IF EXISTS GOVERNANCE.DATA_QUALITY_LOG;"

echo ">> Tables dropped."

# ============================================================
# Step 5: Drop stream and stage
# ============================================================
header "Dropping Stream & Stage"

run_sql "DROP STREAM IF EXISTS BRONZE.STREAM_DATA_FILES;"
run_sql "DROP STAGE IF EXISTS BRONZE.DATA_STAGE;"
run_sql "DROP STAGE IF EXISTS BRONZE.ICEBERG_STAGE;"
run_sql "DROP FILE FORMAT IF EXISTS BRONZE.CSV_FORMAT;"
run_sql "DROP FILE FORMAT IF EXISTS BRONZE.PARQUET_FORMAT;"

echo ">> Stream, stages, and file formats dropped."

# ============================================================
# Step 6: Drop masking policies
# ============================================================
header "Dropping Masking Policies"

run_sql "DROP MASKING POLICY IF EXISTS GOVERNANCE.MASK_NAME;"
run_sql "DROP MASKING POLICY IF EXISTS GOVERNANCE.MASK_EMAIL;"
run_sql "DROP MASKING POLICY IF EXISTS GOVERNANCE.MASK_PHONE;"
run_sql "DROP MASKING POLICY IF EXISTS GOVERNANCE.MASK_LOCATION;"
run_sql "DROP MASKING POLICY IF EXISTS GOVERNANCE.MASK_FINANCIAL_ID;"
run_sql "DROP MASKING POLICY IF EXISTS GOVERNANCE.MASK_AMOUNT;"

echo ">> Masking policies dropped."

# ============================================================
# Step 7: Drop schemas
# ============================================================
header "Dropping Schemas"

run_sql "DROP SCHEMA IF EXISTS BRONZE;"
run_sql "DROP SCHEMA IF EXISTS SILVER;"
run_sql "DROP SCHEMA IF EXISTS GOLD;"
run_sql "DROP SCHEMA IF EXISTS GOVERNANCE;"

echo ">> Schemas dropped."

# ============================================================
# DONE
# ============================================================
header "ALL OBJECTS DROPPED"
echo "Database ${DB} has been cleaned. Only the PUBLIC schema remains."
echo ""

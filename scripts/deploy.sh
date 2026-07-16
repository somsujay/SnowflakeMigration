#!/bin/bash
# ============================================================
# deploy.sh
# Environment-aware deployment orchestrator for Snowflake SQL objects.
#
# Usage:
#   bash scripts/deploy.sh --env=dev
#   bash scripts/deploy.sh --env=qa
#   bash scripts/deploy.sh --env=preprod
#   bash scripts/deploy.sh --env=prod --dry-run
#
# Reads target database/warehouse/connection from environments.yml
# and deploys SQL scripts 01–11 in order.
# ============================================================

set -euo pipefail

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SQL_DIR="${PROJECT_DIR}/Snowflake_Scripts"
ENV_FILE="${PROJECT_DIR}/environments.yml"

# --- Parse arguments ---
ENV=""
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --env=*)
            ENV="${arg#*=}"
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
    esac
done

if [[ -z "$ENV" ]]; then
    echo "ERROR: --env is required."
    echo "Usage: bash scripts/deploy.sh --env=dev|qa|preprod|prod [--dry-run]"
    exit 1
fi

# --- Read environment config ---
parse_env_value() {
    local key="$1"
    awk -v env="$ENV" -v key="$key" '
        $0 ~ "^"env":" { found=1; next }
        found && /^[a-z]/ { found=0 }
        found && $1 == key":" { print $2 }
    ' "$ENV_FILE"
}

DB=$(parse_env_value "database")
WH=$(parse_env_value "warehouse")
CONN=$(parse_env_value "connection")

if [[ -z "$DB" || -z "$WH" || -z "$CONN" ]]; then
    echo "ERROR: Could not parse environment '${ENV}' from ${ENV_FILE}"
    echo "Available environments: dev, qa, preprod, prod"
    exit 1
fi

# --- Verify SQL directory ---
if [[ ! -d "$SQL_DIR" ]]; then
    echo "ERROR: SQL directory not found at ${SQL_DIR}"
    exit 1
fi

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

    if [[ ! -f "$file" ]]; then
        echo "   WARN: File not found, skipping: $(basename "$file")"
        return 0
    fi

    echo ">> Deploying: $(basename "$file") — ${desc}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "   [DRY-RUN] Would execute against ${DB}"
        return 0
    fi

    snow sql -c "$CONN" --database "$DB" --warehouse "$WH" -f "$file"
    echo "   [OK]"
    echo ""
}

# ============================================================
# DEPLOY
# ============================================================
header "DEPLOY TO ${ENV^^} (${DB})"

echo "Environment: ${ENV}"
echo "Database:    ${DB}"
echo "Warehouse:   ${WH}"
echo "Connection:  ${CONN}"
echo "Dry-run:     ${DRY_RUN}"
echo "SQL Dir:     ${SQL_DIR}"
echo ""

if [[ "$ENV" == "prod" && "$DRY_RUN" != "true" ]]; then
    echo "WARNING: Deploying to PRODUCTION environment."
    echo "Ensure this deployment has been approved through the proper channels."
    echo ""
fi

# Deploy scripts in order
run_sql_file "${SQL_DIR}/01_setup_schemas.sql" \
    "Schemas (BRONZE, SILVER, GOLD, GOVERNANCE)"

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
if [[ "$DRY_RUN" == "true" ]]; then
    header "DRY-RUN COMPLETE"
    echo "No changes were made. Re-run without --dry-run to deploy."
else
    header "DEPLOYMENT COMPLETE: ${ENV^^}"
    echo "Deployed 11 SQL scripts to ${DB}."
    echo ""
    echo "Next: Run smoke tests with:"
    echo "  bash scripts/run_smoke_tests.sh --env=${ENV}"
fi

exit 0

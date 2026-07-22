#!/bin/bash
# ============================================================
# deploy_schemachange.sh
# Environment-aware deployment using schemachange.
#
# Usage:
#   bash scripts/deploy_schemachange.sh --env=dev
#   bash scripts/deploy_schemachange.sh --env=qa
#   bash scripts/deploy_schemachange.sh --env=prod --dry-run
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
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
    echo "Usage: bash scripts/deploy_schemachange.sh --env=dev|qa|preprod|prod [--dry-run]"
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
    exit 1
fi

# --- Resolve Snowflake credentials ---
SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT:-}"
SNOWFLAKE_USER="${SNOWFLAKE_USER:-}"
SNOWFLAKE_PRIVATE_KEY_PATH="${SNOWFLAKE_PRIVATE_KEY_PATH:-${HOME}/.snowflake/ci_key.p8}"
SNOWFLAKE_ROLE="${SNOWFLAKE_ROLE:-SYSADMIN}"
SNOWFLAKE_WAREHOUSE="${SNOWFLAKE_WAREHOUSE:-$WH}"

if [[ -z "$SNOWFLAKE_ACCOUNT" || -z "$SNOWFLAKE_USER" ]]; then
    echo "ERROR: SNOWFLAKE_ACCOUNT and SNOWFLAKE_USER environment variables must be set."
    echo "For local development, export these before running this script."
    exit 1
fi

if [[ ! -f "$SNOWFLAKE_PRIVATE_KEY_PATH" ]]; then
    echo "ERROR: Private key file not found at ${SNOWFLAKE_PRIVATE_KEY_PATH}"
    echo "Set SNOWFLAKE_PRIVATE_KEY_PATH to point to your .p8 key file."
    exit 1
fi

# --- Display deployment info ---
echo ""
echo "============================================================"
echo "  SCHEMACHANGE DEPLOY TO ${ENV^^} (${DB})"
echo "============================================================"
echo ""
echo "Environment:  ${ENV}"
echo "Database:     ${DB}"
echo "Warehouse:    ${WH}"
echo "Role:         ${SNOWFLAKE_ROLE}"
echo "Key file:     ${SNOWFLAKE_PRIVATE_KEY_PATH}"
echo "Dry-run:      ${DRY_RUN}"
echo ""

# --- Build schemachange command ---
SCHEMACHANGE_CMD="schemachange deploy"
SCHEMACHANGE_CMD+=" --root-folder ${PROJECT_DIR}/banking"
SCHEMACHANGE_CMD+=" --snowflake-account ${SNOWFLAKE_ACCOUNT}"
SCHEMACHANGE_CMD+=" --snowflake-user ${SNOWFLAKE_USER}"
SCHEMACHANGE_CMD+=" --snowflake-role ${SNOWFLAKE_ROLE}"
SCHEMACHANGE_CMD+=" --snowflake-warehouse ${SNOWFLAKE_WAREHOUSE}"
SCHEMACHANGE_CMD+=" --snowflake-database ${DB}"
SCHEMACHANGE_CMD+=" --change-history-table ${DB}.METADATA.SCHEMACHANGE_HISTORY"
SCHEMACHANGE_CMD+=" --vars '{\"database\": \"${DB}\", \"warehouse\": \"${WH}\", \"role\": \"${SNOWFLAKE_ROLE}\", \"environment\": \"${ENV}\"}'"
SCHEMACHANGE_CMD+=" --create-change-history-table"
SCHEMACHANGE_CMD+=" --autocommit"

# Authentication via private key
SCHEMACHANGE_CMD+=" --snowflake-private-key-path ${SNOWFLAKE_PRIVATE_KEY_PATH}"

if [[ "$DRY_RUN" == "true" ]]; then
    SCHEMACHANGE_CMD+=" --dry-run"
fi

# --- Execute ---
echo ">> Running schemachange..."
echo ""
eval "$SCHEMACHANGE_CMD"

# --- Summary ---
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
    echo "============================================================"
    echo "  DRY-RUN COMPLETE"
    echo "============================================================"
    echo "No changes were made. Re-run without --dry-run to deploy."
else
    echo "============================================================"
    echo "  DEPLOYMENT COMPLETE: ${ENV^^}"
    echo "============================================================"
    echo "All migrations applied to ${DB}."
    echo ""
    echo "Next: Run smoke tests with:"
    echo "  bash scripts/run_smoke_tests.sh --env=${ENV}"
fi

exit 0

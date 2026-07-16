#!/bin/bash
# ============================================================
# rollback.sh
# Rollback a Snowflake deployment to a specific git version.
#
# Usage:
#   bash scripts/rollback.sh --env=preprod --version=v1.2.0
#   bash scripts/rollback.sh --env=prod --version=abc123f
#
# Checks out the SQL scripts from the specified tag/commit,
# re-deploys them, and runs smoke tests.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_DIR}/environments.yml"

# --- Parse arguments ---
ENV=""
VERSION=""

for arg in "$@"; do
    case $arg in
        --env=*)
            ENV="${arg#*=}"
            ;;
        --version=*)
            VERSION="${arg#*=}"
            ;;
    esac
done

if [[ -z "$ENV" || -z "$VERSION" ]]; then
    echo "ERROR: Both --env and --version are required."
    echo "Usage: bash scripts/rollback.sh --env=preprod|prod --version=<tag-or-sha>"
    exit 1
fi

if [[ "$ENV" != "preprod" && "$ENV" != "prod" ]]; then
    echo "ERROR: Rollback is only supported for preprod and prod environments."
    echo "For dev/qa, simply re-push your branch."
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

# --- Validate git version exists ---
cd "$PROJECT_DIR"

if ! git rev-parse --verify "$VERSION" >/dev/null 2>&1; then
    echo "ERROR: Git ref '${VERSION}' not found."
    echo "Use a valid tag (e.g., v1.2.0) or commit SHA."
    exit 1
fi

RESOLVED_SHA=$(git rev-parse "$VERSION")

echo ""
echo "============================================================"
echo "  ROLLBACK: ${ENV^^} → ${VERSION} (${RESOLVED_SHA:0:8})"
echo "============================================================"
echo ""
echo "Database:  ${DB}"
echo "Warehouse: ${WH}"
echo "Target:    ${VERSION} (${RESOLVED_SHA:0:8})"
echo ""

# --- Create a temporary worktree with the target version ---
ROLLBACK_DIR=$(mktemp -d)
trap "rm -rf $ROLLBACK_DIR" EXIT

echo ">> Extracting SQL scripts from ${VERSION}..."
git archive "$RESOLVED_SHA" -- Snowflake_Scripts/ | tar -x -C "$ROLLBACK_DIR"

ROLLBACK_SQL_DIR="${ROLLBACK_DIR}/Snowflake_Scripts"

if [[ ! -d "$ROLLBACK_SQL_DIR" ]]; then
    echo "ERROR: Snowflake_Scripts/ not found in version ${VERSION}"
    exit 1
fi

# --- Deploy the old version ---
echo ">> Deploying SQL scripts from ${VERSION} to ${DB}..."
echo ""

deploy_file() {
    local file="$1"
    local desc="$2"
    if [[ -f "$file" ]]; then
        echo ">> Deploying: $(basename "$file") — ${desc}"
        snow sql -c "$CONN" --database "$DB" --warehouse "$WH" -f "$file"
        echo "   [OK]"
    fi
}

deploy_file "${ROLLBACK_SQL_DIR}/01_setup_schemas.sql" "Schemas"
deploy_file "${ROLLBACK_SQL_DIR}/02_bronze_tables.sql" "Bronze tables"
deploy_file "${ROLLBACK_SQL_DIR}/03_silver_tables.sql" "Silver tables"
deploy_file "${ROLLBACK_SQL_DIR}/04_gold_tables.sql" "Gold tables"
deploy_file "${ROLLBACK_SQL_DIR}/05_silver_procedures.sql" "Silver procedures"
deploy_file "${ROLLBACK_SQL_DIR}/06_gold_procedures.sql" "Gold procedures"
deploy_file "${ROLLBACK_SQL_DIR}/07_orchestration.sql" "Orchestration"
deploy_file "${ROLLBACK_SQL_DIR}/08_seed_data.sql" "Seed data"
deploy_file "${ROLLBACK_SQL_DIR}/09_masking_policies.sql" "Masking policies"
deploy_file "${ROLLBACK_SQL_DIR}/10_data_quality.sql" "Data quality"
deploy_file "${ROLLBACK_SQL_DIR}/11_iceberg_objects.sql" "Iceberg objects"

echo ""

# --- Run smoke tests ---
echo ">> Running smoke tests..."
bash "${SCRIPT_DIR}/run_smoke_tests.sh" --env="$ENV"

echo ""
echo "============================================================"
echo "  ROLLBACK COMPLETE: ${ENV^^} → ${VERSION}"
echo "============================================================"
echo ""
echo "Rolled back ${DB} to version ${VERSION} (${RESOLVED_SHA:0:8})."
echo "Smoke tests passed."

exit 0

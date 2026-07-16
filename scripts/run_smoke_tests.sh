#!/bin/bash
# ============================================================
# run_smoke_tests.sh
# Run post-deployment smoke tests against a Snowflake environment
#
# Usage:
#   bash scripts/run_smoke_tests.sh --env=dev
#   bash scripts/run_smoke_tests.sh --env=qa
#
# Executes tests/smoke_test.sql with database placeholder substituted.
# Exits non-zero if any query fails.
# ============================================================

set -e

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_FILE="${PROJECT_DIR}/tests/smoke_test.sql"
ENV_FILE="${PROJECT_DIR}/environments.yml"

# --- Parse arguments ---
ENV=""

for arg in "$@"; do
    case $arg in
        --env=*)
            ENV="${arg#*=}"
            ;;
    esac
done

if [[ -z "$ENV" ]]; then
    echo "ERROR: --env is required. Usage: bash run_smoke_tests.sh --env=dev|qa"
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

# --- Run smoke tests ---
echo ""
echo "============================================================"
echo "  SMOKE TESTS: ${ENV} (${DB})"
echo "============================================================"
echo ""

echo ">> Substituting {{DATABASE_NAME}} with ${DB}..."
echo ">> Executing smoke tests..."
echo ""

# Substitute placeholder and run
sed "s/{{DATABASE_NAME}}/${DB}/g" "$TEST_FILE" | \
    snow sql -c "$CONN" --database "$DB" --warehouse "$WH" -i

EXIT_CODE=$?

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "============================================================"
    echo "  SMOKE TESTS PASSED"
    echo "============================================================"
else
    echo "============================================================"
    echo "  SMOKE TESTS FAILED (exit code: ${EXIT_CODE})"
    echo "============================================================"
fi

exit $EXIT_CODE

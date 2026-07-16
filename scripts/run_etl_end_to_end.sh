#!/bin/bash
# ============================================================
# run_etl_end_to_end.sh
# End-to-end ETL pipeline wrapper
#
# Usage:
#   bash run_etl_end_to_end.sh                 # Default: CSV source
#   bash run_etl_end_to_end.sh --source=csv    # Explicit: CSV source
#   bash run_etl_end_to_end.sh --source=iceberg # Iceberg/Parquet source
#
# Runs the full pipeline by calling individual scripts:
#   1. run_historical.sh  (reset + history load + ETL + validate)
#   2. run_incremental.sh (incremental load + ETL + validate)
#   3. streamlit_start.sh (launch dashboard)
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

echo ""
echo "============================================================"
echo "  END-TO-END ETL PIPELINE (source: ${SOURCE})"
echo "============================================================"
echo ""

# --- Step 1: Historical Load ---
bash "${SCRIPT_DIR}/run_historical.sh" --source="${SOURCE}"

# --- Step 2: Incremental Load ---
bash "${SCRIPT_DIR}/run_incremental.sh" --source="${SOURCE}"

# --- Step 3: Start Streamlit ---
bash "${SCRIPT_DIR}/streamlit_start.sh"

echo ""
echo "============================================================"
echo "  END-TO-END PIPELINE COMPLETE (source: ${SOURCE})"
echo "============================================================"
echo ""
echo "All phases executed successfully."
echo "Dashboard running at http://localhost:8501"
echo ""
echo "To stop the dashboard: bash ${SCRIPT_DIR}/streamlit_stop.sh"
echo "To drop all objects:   bash ${SCRIPT_DIR}/drop_objects.sh --confirm"
echo ""

#!/bin/bash
# ============================================================
# streamlit_start.sh
# Start (or restart) the Streamlit Analytics Dashboard
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STREAMLIT_APP="${PROJECT_DIR}/streamlit_app/Analytics.py"
PID_FILE="${SCRIPT_DIR}/.streamlit.pid"

# --- Stop any existing instance ---
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo ">> Stopping existing Streamlit process (PID: ${OLD_PID})..."
        kill "$OLD_PID" 2>/dev/null
        sleep 2
    fi
    rm -f "$PID_FILE"
fi

# Also kill any stray streamlit processes for this app
pkill -f "streamlit run.*Analytics.py" 2>/dev/null || true
sleep 1

# --- Start Streamlit ---
if [ ! -f "$STREAMLIT_APP" ]; then
    echo "ERROR: Streamlit app not found at ${STREAMLIT_APP}"
    exit 1
fi

echo "============================================================"
echo "  Starting Streamlit Analytics Dashboard"
echo "============================================================"
echo ""
echo ">> App: ${STREAMLIT_APP}"
echo ">> URL: http://localhost:8501"
echo ""

nohup streamlit run "$STREAMLIT_APP" --server.port 8501 > "${SCRIPT_DIR}/.streamlit.log" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"

echo ">> Streamlit started (PID: ${NEW_PID})"
echo ">> Log: ${SCRIPT_DIR}/.streamlit.log"
echo ">> PID file: ${PID_FILE}"
echo ""
echo "To stop: bash ${SCRIPT_DIR}/streamlit_stop.sh"

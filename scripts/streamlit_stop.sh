#!/bin/bash
# ============================================================
# streamlit_stop.sh
# Stop the running Streamlit Analytics Dashboard
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.streamlit.pid"

echo "============================================================"
echo "  Stopping Streamlit Analytics Dashboard"
echo "============================================================"
echo ""

STOPPED=false

# Try PID file first
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo ">> Stopping Streamlit (PID: ${PID})..."
        kill "$PID" 2>/dev/null
        sleep 2
        if kill -0 "$PID" 2>/dev/null; then
            echo ">> Force killing (PID: ${PID})..."
            kill -9 "$PID" 2>/dev/null
        fi
        STOPPED=true
    else
        echo ">> PID ${PID} is not running."
    fi
    rm -f "$PID_FILE"
fi

# Also kill any stray streamlit processes for this app
PIDS=$(pgrep -f "streamlit run.*Analytics.py" 2>/dev/null)
if [ -n "$PIDS" ]; then
    echo ">> Killing remaining Streamlit processes: ${PIDS}"
    pkill -f "streamlit run.*Analytics.py" 2>/dev/null
    STOPPED=true
fi

if [ "$STOPPED" = true ]; then
    echo ""
    echo ">> Streamlit stopped successfully."
else
    echo ">> No running Streamlit process found."
fi

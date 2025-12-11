#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.keylogger.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "⚠️  Aucun keylogger en cours"
    exit 1
fi

PID=$(cat "$PID_FILE")

if ps -p $PID > /dev/null 2>&1; then
    kill $PID
    rm "$PID_FILE"
    echo "✅ Keylogger arrêté (PID: $PID)"
else
    echo "⚠️  Le processus $PID n'existe plus"
    rm "$PID_FILE"
fi

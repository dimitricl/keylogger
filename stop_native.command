#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.mac_client.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "[!] Aucun PID trouvé."
  exit 0
fi

PID=$(cat "$PID_FILE")
if ps -p "$PID" >/dev/null 2>&1; then
  kill "$PID" >/dev/null 2>&1 || true
  echo "[✓] Processus mac_client (PID $PID) arrêté."
else
  echo "[!] Aucun processus mac_client actif pour PID $PID."
fi

rm -f "$PID_FILE"
exit 0


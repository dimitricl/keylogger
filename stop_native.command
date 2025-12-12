#!/bin/zsh
cd "$(dirname "$0")"

echo "Arrêt du keylogger macOS..."

pids=$(ps aux | grep "KeyloggerPro.app/Contents/MacOS/mac_client" | grep -v grep | awk '{print $2}')

if [ -z "$pids" ]; then
  echo "[!] Aucun PID trouvé."
else
  for pid in $pids; do
    echo "[✓] Processus mac_client (PID $pid) arrêté."
    kill "$pid" 2>/dev/null || true
  done
fi


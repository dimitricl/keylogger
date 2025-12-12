#!/bin/bash
DIR=$(cd "$(dirname "$0")"; pwd)

echo "Arrêt du système de mise à jour..."

# Tuer le processus par son nom exact
killall MacUpdateSystem 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Programme arrêté avec succès."
else
    echo "⚠️ Le programme n'était pas en cours d'exécution."
fi

# Petite pause pour lire le message
sleep 2

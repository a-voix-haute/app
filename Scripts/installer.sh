#!/bin/bash
# Installe À Voix Haute dans /Applications.
#
#     Scripts/installer.sh                 installation complète
#     Scripts/installer.sh --sans-demarrage  sans lancement à l'ouverture de session
#     Scripts/installer.sh --desinstaller    retire tout
#
# L'application est installée sous son nom accentué — « À Voix Haute.app » —
# tandis que son exécutable reste « AVoixHaute », sans accent : macOS distingue
# le nom du bundle de celui du binaire, et seul le premier est visible.

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOM_INSTALLE="À Voix Haute.app"
DESTINATION="/Applications/$NOM_INSTALLE"
LIEN_HELPER="$HOME/.local/bin/lire"
AGENT="$HOME/Library/LaunchAgents/fr.dimitri.AVoixHaute.plist"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"

AVEC_DEMARRAGE=true
DESINSTALLER=false

for argument in "$@"; do
    case "$argument" in
        --sans-demarrage) AVEC_DEMARRAGE=false ;;
        --desinstaller)   DESINSTALLER=true ;;
        *) echo "Option inconnue : $argument" >&2; exit 1 ;;
    esac
done

# --- Désinstallation --------------------------------------------------------

if $DESINSTALLER; then
    echo "Désinstallation…"

    pkill -x "AVoixHaute" 2>/dev/null || true
    sleep 1

    if [ -f "$AGENT" ]; then
        launchctl unload "$AGENT" 2>/dev/null || true
        rm -f "$AGENT"
        echo "  agent de démarrage retiré"
    fi

    [ -L "$LIEN_HELPER" ] && rm -f "$LIEN_HELPER" && echo "  helper retiré"

    if [ -d "$DESTINATION" ]; then
        "$LSREGISTER" -u "$DESTINATION" 2>/dev/null || true
        rm -rf "$DESTINATION"
        echo "  application retirée"
    fi

    rm -rf "$HOME/Library/Application Support/AVoixHaute"
    rm -f "$HOME/Library/Logs/AVoixHaute.log"
    defaults delete fr.dimitri.AVoixHaute 2>/dev/null || true
    "$PBS" -flush 2>/dev/null || true

    echo
    echo "Désinstallation terminée."
    echo "L'autorisation Accessibilité est à retirer manuellement dans"
    echo "Réglages Système → Confidentialité et sécurité → Accessibilité."
    exit 0
fi

# --- Installation -----------------------------------------------------------

APP_SOURCE="$RACINE/build/Build/Products/Release/AVoixHaute.app"

if [ ! -d "$APP_SOURCE" ]; then
    echo "Application Release introuvable. Compilation…"
    "$RACINE/Scripts/construire.sh"
fi

if [ ! -d "$APP_SOURCE" ]; then
    echo "Erreur : compilation impossible." >&2
    exit 1
fi

# Accolades obligatoires : sans elles, bash agrège le caractère « … » qui suit
# au nom de la variable.
echo "Installation de ${NOM_INSTALLE}…"

# L'application ne doit pas tourner pendant son remplacement.
if pgrep -x "AVoixHaute" >/dev/null; then
    echo "  arrêt de l'instance en cours"
    pkill -x "AVoixHaute" || true
    sleep 1
fi

[ -d "$DESTINATION" ] && rm -rf "$DESTINATION"
cp -R "$APP_SOURCE" "$DESTINATION"
echo "  installée dans /Applications"

# Le fichier de quarantaine ferait afficher un avertissement au premier
# lancement ; l'application vient d'être compilée localement, elle n'a pas
# transité par Internet.
xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true

# --- Helper en ligne de commande -------------------------------------------

mkdir -p "$(dirname "$LIEN_HELPER")"
ln -sf "$DESTINATION/Contents/Resources/lire" "$LIEN_HELPER"
echo "  helper lié : $LIEN_HELPER"

# --- Enregistrement système -------------------------------------------------

"$LSREGISTER" -f "$DESTINATION"
"$PBS" -flush 2>/dev/null || true
echo "  service « Lire à voix haute » enregistré"

# --- Lancement à l'ouverture de session ------------------------------------

if $AVEC_DEMARRAGE; then
    mkdir -p "$(dirname "$AGENT")"
    cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>fr.dimitri.AVoixHaute</string>
	<!-- `open -b` plutôt que le binaire directement : LaunchServices refuse
	     une seconde instance et se contente d'activer celle qui tourne, là où
	     un lancement direct en démarrerait une deuxième, qui se disputerait le
	     socket avec la première. -->
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-b</string>
		<string>fr.dimitri.AVoixHaute</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<!-- Pas de KeepAlive : l'utilisateur doit pouvoir quitter l'application
	     sans que launchd la relance aussitôt. -->
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST

    launchctl unload "$AGENT" 2>/dev/null || true
    launchctl load "$AGENT"
    echo "  lancement à l'ouverture de session activé"
fi

# --- Démarrage --------------------------------------------------------------

open "$DESTINATION"

# Le premier lancement depuis /Applications demande quelques secondes : macOS
# vérifie la signature et enregistre le bundle avant de rendre la main.
DEMARREE=false
for _ in $(seq 1 10); do
    sleep 1
    if pgrep -x "AVoixHaute" >/dev/null; then
        DEMARREE=true
        break
    fi
done

echo
if $DEMARREE; then
    echo "Installation terminée, application lancée."
else
    echo "Installation terminée, mais l'application n'a pas démarré."
    echo "Consultez ~/Library/Logs/AVoixHaute.log"
fi

echo
echo "Usage :"
echo "  • icône ⌁ dans la barre de menus"
echo "  • sélection + clic droit → Services → « Lire à voix haute »"
echo "  • raccourci ⌃⌥L sur une sélection"
echo "  • terminal : pbpaste | lire, lire fichier.md, lire --stop"
echo
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
    echo "Ajoutez ~/.local/bin à votre PATH pour la commande lire :"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

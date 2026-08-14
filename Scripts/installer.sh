#!/bin/bash
# Installe À Voix Haute dans /Applications.
#
#     Scripts/installer.sh                 installation complète
#     Scripts/installer.sh --sans-demarrage  sans lancement à l'ouverture de session
#     Scripts/installer.sh --desinstaller    retire tout
#
# Chaque option accepte aussi sa forme anglaise — `--uninstall`,
# `--no-startup` —, et la commande installée répond dans les six langues de
# l'application : `lire`, `read-aloud`, `leer`, `vorlesen`, `leggi`, `ler`.
#
# Ces alias sont permanents et non liés à la langue du système. C'est
# délibéré : une commande notée dans un script ou une documentation doit
# fonctionner sur toutes les machines, or un identifiant qui suivrait la langue
# du poste casserait dès qu'il en change.
#
# L'application est installée sous son nom accentué — « À Voix Haute.app » —
# tandis que son exécutable reste « AVoixHaute », sans accent : macOS distingue
# le nom du bundle de celui du binaire, et seul le premier est visible.

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOM_INSTALLE="À Voix Haute.app"
DESTINATION="/Applications/$NOM_INSTALLE"
DOSSIER_HELPERS="$HOME/.local/bin"

# Noms sous lesquels la commande répond, un par langue de l'application.
#
# « read-aloud » et non « read » : `read` est une primitive de bash et de zsh,
# et une primitive l'emporte toujours sur un fichier du PATH — le lien serait
# silencieusement sans effet, pire qu'absent. « leggi » et « ler » ne se
# heurtent à rien, « leer » et « vorlesen » non plus.
NOMS_HELPER=(lire read-aloud leer vorlesen leggi ler)
AGENT="$HOME/Library/LaunchAgents/app.avoixhaute.player.plist"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"

AVEC_DEMARRAGE=true
DESINSTALLER=false

for argument in "$@"; do
    case "$argument" in
        --sans-demarrage|--no-startup) AVEC_DEMARRAGE=false ;;
        --desinstaller|--uninstall)    DESINSTALLER=true ;;
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

    # Seuls les liens symboliques sont retirés : un fichier ordinaire portant
    # l'un de ces noms n'est pas le nôtre et ne nous appartient pas.
    retires=0
    for nom in "${NOMS_HELPER[@]}"; do
        if [ -L "$DOSSIER_HELPERS/$nom" ]; then
            rm -f "$DOSSIER_HELPERS/$nom"
            retires=$((retires + 1))
        fi
    done
    [ "$retires" -gt 0 ] && echo "  helpers retirés ($retires)"

    if [ -d "$DESTINATION" ]; then
        "$LSREGISTER" -u "$DESTINATION" 2>/dev/null || true
        rm -rf "$DESTINATION"
        echo "  application retirée"
    fi

    rm -rf "$HOME/Library/Application Support/AVoixHaute"
    rm -f "$HOME/Library/Logs/AVoixHaute.log"
    rm -rf "$HOME/Library/Caches/app.avoixhaute.player"
    rm -rf "$HOME/Library/Caches/fr.dimitri.AVoixHaute"

    # Les deux identifiants sont purgés : celui d'aujourd'hui et celui d'avant
    # la 2.0.0. Le renommage précédent — « Lecteur » vers « À Voix Haute » —
    # avait laissé ses préférences derrière lui, faute de cette ligne.
    #
    # La suite de tests crée un domaine par exécution, « …tests.<UUID> » : sans
    # le motif, ils s'accumulent indéfiniment.
    for domaine in app.avoixhaute.player fr.dimitri.AVoixHaute fr.dimitri.Lecteur; do
        defaults delete "$domaine" 2>/dev/null || true
        rm -f "$HOME/Library/Preferences/$domaine.plist"
        rm -f "$HOME/Library/Preferences/$domaine".tests.*.plist
    done
    # `cfprefsd` garde les préférences en mémoire et réécrirait les fichiers
    # que l'on vient de supprimer.
    killall cfprefsd 2>/dev/null || true

    "$PBS" -flush 2>/dev/null || true

    echo
    echo "Désinstallation terminée."
    echo "L'autorisation Accessibilité est à retirer manuellement dans"
    echo "Réglages Système → Confidentialité et sécurité → Accessibilité."
    exit 0
fi

# --- Installation -----------------------------------------------------------

APP_SOURCE="$RACINE/build/Build/Products/Release/AVoixHaute.app"

# La compilation est systématique, et non conditionnée à l'absence de
# `build/`. Un dossier présent mais antérieur aux sources ferait installer une
# version périmée, que l'on testerait alors sans le savoir — le cas s'est
# produit avec les catalogues de traduction et le helper. `xcodebuild` sait de
# lui-même ne rien refaire quand rien n'a changé, le coût est donc nul.
#
# Corollaire : `xcodebuild … test` compile en Debug dans le même `build/` et
# laisse la cible Release dans un état intermédiaire. Lancer les tests puis
# installer sans repasser par ici copierait ce résultat partiel. Réinstaller
# après les tests, et non l'inverse.
echo "Compilation…"
"$RACINE/Scripts/construire.sh"

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

# `rm -rf` sans test préalable : sous `set -e`, un `[ -d … ] && rm` s'évaluant
# à faux vaut un échec et interromprait le script juste avant la copie.
rm -rf "$DESTINATION"
cp -R "$APP_SOURCE" "$DESTINATION"
echo "  installée dans /Applications"

# Le fichier de quarantaine ferait afficher un avertissement au premier
# lancement ; l'application vient d'être compilée localement, elle n'a pas
# transité par Internet.
xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true

# --- Helper en ligne de commande -------------------------------------------

mkdir -p "$DOSSIER_HELPERS"
for nom in "${NOMS_HELPER[@]}"; do
    ln -sf "$DESTINATION/Contents/Resources/lire" "$DOSSIER_HELPERS/$nom"
done
echo "  helper lié : $DOSSIER_HELPERS/{$(IFS=,; echo "${NOMS_HELPER[*]}")}"

# --- Enregistrement système -------------------------------------------------

"$LSREGISTER" -f "$DESTINATION"
"$PBS" -flush 2>/dev/null || true
echo "  service « Lire à voix haute » enregistré"

# --- Lancement à l'ouverture de session ------------------------------------

# L'agent de la 1.x porte l'ancien identifiant : sans ce retrait, launchd
# continuerait de charger une définition pointant sur un bundle qui ne se
# déclare plus sous ce nom.
AGENT_HERITE="$HOME/Library/LaunchAgents/fr.dimitri.AVoixHaute.plist"
VENAIT_DE_LA_1X=false
if [ -f "$AGENT_HERITE" ]; then
    launchctl unload "$AGENT_HERITE" 2>/dev/null || true
    rm -f "$AGENT_HERITE"
    VENAIT_DE_LA_1X=true
    echo "  ancien agent de démarrage retiré"
fi

if $AVEC_DEMARRAGE; then
    mkdir -p "$(dirname "$AGENT")"
    cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>app.avoixhaute.player</string>
	<!-- `open -b` plutôt que le binaire directement : LaunchServices refuse
	     une seconde instance et se contente d'activer celle qui tourne, là où
	     un lancement direct en démarrerait une deuxième, qui se disputerait le
	     socket avec la première. -->
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-b</string>
		<string>app.avoixhaute.player</string>
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
if $VENAIT_DE_LA_1X; then
    echo "Mise à jour depuis la 1.x : l'identifiant de l'application a changé."
    echo "Vos réglages ont été repris, mais macOS voit une application nouvelle :"
    echo "l'autorisation Accessibilité est à réaccorder dans"
    echo "Réglages Système → Confidentialité et sécurité → Accessibilité."
    echo "Sans elle, le raccourci ⌃⌥L lit le presse-papiers au lieu de la sélection."
    echo
fi

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

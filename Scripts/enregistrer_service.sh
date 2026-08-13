#!/bin/bash
# Fait apparaître « Lire à voix haute » dans le menu Services de macOS.
#
# En développement, l'application change d'emplacement à chaque compilation :
# LaunchServices garde des entrées périmées et le service n'apparaît pas, ou
# pointe vers une version disparue. Ce script remet les choses en ordre.

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# `pbs` n'est pas dans le PATH : son chemin absolu est obligatoire.
PBS="/System/Library/CoreServices/pbs"

for CANDIDAT in \
    "/Applications/Lecteur.app" \
    "$RACINE/build/Build/Products/Release/Lecteur.app" \
    "$RACINE/build/Build/Products/Debug/Lecteur.app"
do
    if [ -d "$CANDIDAT" ]; then
        APP="$CANDIDAT"
        break
    fi
done

if [ -z "${APP:-}" ]; then
    echo "Erreur : Lecteur.app introuvable. Compilez d'abord le projet." >&2
    exit 1
fi

echo "Application : $APP"

# Purge les entrées périmées des versions précédentes.
echo "Nettoyage des enregistrements obsolètes…"
"$LSREGISTER" -u "$APP" 2>/dev/null || true

echo "Enregistrement de l'application…"
"$LSREGISTER" -f "$APP"

echo "Rafraîchissement du menu Services…"
"$PBS" -flush 2>/dev/null || true

# L'application doit tourner pour que son fournisseur soit joignable.
if ! pgrep -f "Lecteur.app/Contents/MacOS/Lecteur" >/dev/null; then
    echo "Lancement de l'application…"
    open "$APP"
    sleep 2
fi

echo
echo "Terminé."
echo
echo "Pour l'essayer : sélectionnez du texte dans Safari, TextEdit ou Notes,"
echo "puis clic droit → Services → « Lire à voix haute »."
echo
echo "Si l'entrée n'apparaît pas :"
echo "  • activez-la dans Réglages Système → Clavier → Raccourcis clavier → Services"
echo "  • ou fermez puis rouvrez l'application où vous testez : le menu Services"
echo "    n'est relu qu'au lancement de chaque application."

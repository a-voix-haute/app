#!/bin/bash
# Installe le helper `lire` dans ~/.local/bin, en le liant à celui que contient
# le bundle de l'application.
#
# Un lien symbolique plutôt qu'une copie : le helper reste ainsi synchronisé
# avec l'application à chaque recompilation.
#
# ~/.local/bin plutôt que /usr/local/bin : ce dernier appartient à root et
# exigerait sudo.

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="$HOME/.local/bin"
LIEN="$DESTINATION/lire"

# Emplacement de l'application : d'abord l'installation, puis la compilation.
for CANDIDAT in \
    "/Applications/AVoixHaute.app" \
    "$RACINE/build/Build/Products/Release/AVoixHaute.app" \
    "$RACINE/build/Build/Products/Debug/AVoixHaute.app"
do
    if [ -x "$CANDIDAT/Contents/Resources/lire" ]; then
        SOURCE="$CANDIDAT/Contents/Resources/lire"
        break
    fi
done

if [ -z "${SOURCE:-}" ]; then
    echo "Erreur : helper introuvable." >&2
    echo "Compilez d'abord le projet : Scripts/construire.sh" >&2
    exit 1
fi

mkdir -p "$DESTINATION"
ln -sf "$SOURCE" "$LIEN"

echo "Helper installé : $LIEN"
echo "            → $SOURCE"

# ~/.local/bin n'est pas toujours dans le PATH.
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$DESTINATION"; then
    echo
    echo "Ajoutez ce dossier à votre PATH, par exemple dans ~/.zshrc :"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
else
    echo
    echo "Essayez :  echo \"Bonjour\" | lire"
fi

#!/bin/bash
# Construit À Voix Haute en configuration Release.
#
#     Scripts/construire.sh              compilation simple
#     Scripts/construire.sh --distribuer signature Developer ID + runtime durci
#
# Le mode distribution prépare l'application pour la notarisation ; sans lui,
# la signature de développement suffit à un usage local.

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RACINE"

PROJET="AVoixHaute.xcodeproj"
SORTIE="$RACINE/build"
DISTRIBUER=false

for argument in "$@"; do
    case "$argument" in
        --distribuer) DISTRIBUER=true ;;
        *) echo "Option inconnue : $argument" >&2; exit 1 ;;
    esac
done

echo "Régénération du projet…"
ruby Scripts/generer_projet.rb >/dev/null

if $DISTRIBUER; then
    IDENTITE="Developer ID Application"
    EQUIPE="5D6QHL72QC"

    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITE"; then
        echo "Erreur : certificat « $IDENTITE » introuvable." >&2
        exit 1
    fi

    echo "Compilation Release (signature de distribution)…"
    xcodebuild -project "$PROJET" \
        -scheme AVoixHaute \
        -configuration Release \
        -derivedDataPath "$SORTIE" \
        CODE_SIGN_IDENTITY="$IDENTITE" \
        DEVELOPMENT_TEAM="$EQUIPE" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_ENTITLEMENTS="Ressources/AVoixHaute.entitlements" \
        ENABLE_HARDENED_RUNTIME=YES \
        OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
        ENABLE_DEBUG_DYLIB=NO \
        build 2>&1 | grep -E "error:|BUILD" || true

    # Le filtre `grep` ci-dessus masque le code de retour de xcodebuild : sans
    # ce test, une compilation en échec passerait pour une réussite et
    # l'installation copierait le build précédent, périmé.
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Échec de la compilation." >&2; exit 1; }

    # get-task-allow autorise l'attachement d'un débogueur : Apple rejette
    # systématiquement une soumission qui le déclare. Xcode l'ajoute d'office
    # en Release, il faut donc resigner sans lui.
    echo "Resignature sans le droit de débogage…"
    codesign --force --sign "$IDENTITE" \
        --entitlements "Ressources/AVoixHaute.entitlements" \
        --options runtime \
        --timestamp \
        "$SORTIE/Build/Products/Release/AVoixHaute.app/Contents/Resources/lire" 2>/dev/null
    codesign --force --sign "$IDENTITE" \
        --entitlements "Ressources/AVoixHaute.entitlements" \
        --options runtime \
        --timestamp \
        "$SORTIE/Build/Products/Release/AVoixHaute.app" 2>/dev/null
else
    echo "Compilation Release…"
    xcodebuild -project "$PROJET" \
        -scheme AVoixHaute \
        -configuration Release \
        -derivedDataPath "$SORTIE" \
        build 2>&1 | grep -E "error:|BUILD" || true

    # Le filtre `grep` ci-dessus masque le code de retour de xcodebuild : sans
    # ce test, une compilation en échec passerait pour une réussite et
    # l'installation copierait le build précédent, périmé.
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Échec de la compilation." >&2; exit 1; }

    # `get-task-allow` autorise n'importe quel processus à s'attacher au
    # débogueur de l'application, donc à lire sa mémoire — le texte en cours
    # de lecture compris. Xcode l'ajoute d'office, y compris en Release.
    #
    # La branche de distribution le retire déjà pour satisfaire Apple ; il
    # n'y a pas de raison qu'une installation locale reste exposée. Signature
    # ad hoc, faute de certificat ici : elle suffit à porter les
    # entitlements.
    echo "Resignature sans le droit de débogage…"
    codesign --force --sign - \
        --entitlements "Ressources/AVoixHaute.entitlements" \
        "$SORTIE/Build/Products/Release/AVoixHaute.app/Contents/Resources/lire" 2>/dev/null
    codesign --force --sign - \
        --entitlements "Ressources/AVoixHaute.entitlements" \
        "$SORTIE/Build/Products/Release/AVoixHaute.app" 2>/dev/null
fi

APP="$SORTIE/Build/Products/Release/AVoixHaute.app"

if [ ! -d "$APP" ]; then
    echo "Erreur : compilation échouée." >&2
    exit 1
fi

echo
echo "Application : $APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier=|Authority=|TeamIdentifier=" | sed 's/^/  /'

if $DISTRIBUER; then
    echo
    echo "Vérification de la signature…"
    if codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | grep -q "satisfies its Designated Requirement"; then
        echo "  signature valide"
    fi
    echo
    echo "Étape suivante : Scripts/notariser.sh"
fi

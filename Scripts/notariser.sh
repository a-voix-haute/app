#!/bin/bash
# Notarise À Voix Haute auprès d'Apple et produit un disque d'installation.
#
#     Scripts/notariser.sh
#
# La notarisation permet à l'application de s'ouvrir sans avertissement sur
# n'importe quel Mac. Elle exige, une fois pour toutes, un profil d'identifiants
# enregistré dans le trousseau :
#
#     xcrun notarytool store-credentials "avoixhaute" \
#         --apple-id VOTRE_IDENTIFIANT_APPLE \
#         --team-id 5D6QHL72QC \
#         --password MOT_DE_PASSE_APPLICATION
#
# Le mot de passe d'application se crée sur appleid.apple.com, rubrique
# « Connexion et sécurité », puis « Mots de passe des apps ». Ce n'est pas le
# mot de passe du compte Apple.

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RACINE"

PROFIL="${LECTEUR_PROFIL_NOTARISATION:-avoixhaute}"
EQUIPE="5D6QHL72QC"
APP="$RACINE/build/Build/Products/Release/AVoixHaute.app"
DISTRIBUTION="$RACINE/build/distribution"
ARCHIVE="$DISTRIBUTION/AVoixHaute.zip"
IMAGE="$DISTRIBUTION/À Voix Haute.dmg"

# --- Vérifications ----------------------------------------------------------

if ! xcrun notarytool history --keychain-profile "$PROFIL" >/dev/null 2>&1; then
    echo "Erreur : profil « $PROFIL » absent du trousseau." >&2
    echo >&2
    echo "Créez-le une fois avec :" >&2
    echo "    xcrun notarytool store-credentials \"$PROFIL\" \\" >&2
    echo "        --apple-id VOTRE_IDENTIFIANT_APPLE \\" >&2
    echo "        --team-id $EQUIPE \\" >&2
    echo "        --password MOT_DE_PASSE_APPLICATION" >&2
    echo >&2
    echo "Le mot de passe d'application se crée sur appleid.apple.com." >&2
    exit 1
fi

if [ ! -d "$APP" ]; then
    echo "Application Release absente. Compilation avec signature de distribution…"
    "$RACINE/Scripts/construire.sh" --distribuer
fi

echo "Vérification de la signature…"
if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
    echo "Erreur : signature invalide. Relancez Scripts/construire.sh --distribuer" >&2
    exit 1
fi

# Le runtime durci est obligatoire pour la notarisation. Il apparaît dans les
# indicateurs de la signature sous la forme « flags=0x10000(runtime) ».
#
# La sortie est capturée avant d'être filtrée : sous `set -o pipefail`, le code
# de retour de codesign ferait échouer le pipeline avant même le test.
DESCRIPTION_SIGNATURE="$(codesign -d --verbose=2 "$APP" 2>&1 || true)"
case "$DESCRIPTION_SIGNATURE" in
    *"0x10000(runtime)"*) ;;
    *)
        echo "Erreur : runtime durci absent. Relancez Scripts/construire.sh --distribuer" >&2
        exit 1
        ;;
esac
echo "  signature et runtime durci vérifiés"

# --- Envoi ------------------------------------------------------------------

mkdir -p "$DISTRIBUTION"
rm -f "$ARCHIVE"

echo
echo "Préparation de l'archive…"
# ditto préserve les liens symboliques et les métadonnées, contrairement à zip.
ditto -c -k --keepParent "$APP" "$ARCHIVE"

echo "Envoi à Apple (quelques minutes)…"
if ! xcrun notarytool submit "$ARCHIVE" \
        --keychain-profile "$PROFIL" \
        --wait \
        --timeout 30m; then
    echo >&2
    echo "La notarisation a échoué. Pour connaître le motif :" >&2
    echo "    xcrun notarytool history --keychain-profile $PROFIL" >&2
    echo "    xcrun notarytool log <identifiant> --keychain-profile $PROFIL" >&2
    exit 1
fi

# --- Agrafage ---------------------------------------------------------------

echo
echo "Agrafage du ticket…"
# Le ticket agrafé permet la vérification hors ligne, sur un Mac sans réseau.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- Image disque -----------------------------------------------------------

echo
echo "Création du disque d'installation…"
rm -f "$IMAGE"

# Le dossier est supprimé juste après la création de l'image, plutôt que par un
# trap : un trap posé ici s'exécuterait à la sortie du script, y compris sur une
# sortie anticipée, alors que l'image a besoin du dossier jusqu'au bout.
MONTAGE="$(mktemp -d)"

cp -R "$APP" "$MONTAGE/À Voix Haute.app"
ln -s /Applications "$MONTAGE/Applications"

hdiutil create \
    -volname "À Voix Haute" \
    -srcfolder "$MONTAGE" \
    -ov -format UDZO \
    "$IMAGE" >/dev/null

rm -rf "$MONTAGE"

# L'image elle-même est signée puis notarisée : c'est elle qui circulera.
codesign --sign "Developer ID Application" --timestamp "$IMAGE"

echo "Notarisation du disque…"
xcrun notarytool submit "$IMAGE" \
    --keychain-profile "$PROFIL" \
    --wait \
    --timeout 30m
xcrun stapler staple "$IMAGE"

echo
echo "Terminé."
echo "  Application : $APP"
echo "  Disque      : $IMAGE"
echo
echo "Le disque s'ouvre sans avertissement sur n'importe quel Mac."

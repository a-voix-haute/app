#!/bin/bash
# Fabrique Ressources/AVoixHaute.icns à partir d'un tracé vectoriel.
#
# L'icône reprend les codes des applications système : carré aux coins arrondis,
# dégradé, et un motif lisible même à seize pixels — ici une onde sonore, forme
# reconnaissable à toutes les tailles, contrairement à un glyphe détaillé.

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRAVAIL="$(mktemp -d)"
JEU="$TRAVAIL/AVoixHaute.iconset"
SVG="$TRAVAIL/icone.svg"

trap 'rm -rf "$TRAVAIL"' EXIT

mkdir -p "$JEU"

cat > "$SVG" <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="fond" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#5E5CE6"/>
      <stop offset="100%" stop-color="#3634A3"/>
    </linearGradient>
    <linearGradient id="lueur" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.28"/>
      <stop offset="55%" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
  </defs>

  <!-- Le rayon suit la courbure des icônes macOS : environ 22 % du côté. -->
  <rect x="72" y="72" width="880" height="880" rx="196" ry="196" fill="url(#fond)"/>
  <rect x="72" y="72" width="880" height="880" rx="196" ry="196" fill="url(#lueur)"/>

  <!-- Onde sonore : sept barres d'amplitudes croissantes puis décroissantes,
       assez épaisses pour rester visibles à seize pixels. -->
  <g fill="#FFFFFF" stroke="none">
    <rect x="252" y="452" width="56" height="120" rx="28"/>
    <rect x="356" y="392" width="56" height="240" rx="28"/>
    <rect x="460" y="312" width="56" height="400" rx="28"/>
    <rect x="564" y="392" width="56" height="240" rx="28"/>
    <rect x="668" y="452" width="56" height="120" rx="28"/>
  </g>
</svg>
SVGEOF

# Rendu aux tailles requises par macOS, en incluant les variantes @2x.
rendre() {
    local taille="$1" nom="$2"
    if command -v rsvg-convert >/dev/null 2>&1; then
        rsvg-convert -w "$taille" -h "$taille" "$SVG" -o "$JEU/$nom"
    else
        # `sips` ne lit pas le SVG : on passe par un PDF, que Quartz sait rendre.
        if [ ! -f "$TRAVAIL/icone.pdf" ]; then
            /usr/bin/qlmanage -t -s 1024 -o "$TRAVAIL" "$SVG" >/dev/null 2>&1 || true
        fi
        if [ -f "$TRAVAIL/icone.svg.png" ]; then
            sips -z "$taille" "$taille" "$TRAVAIL/icone.svg.png" --out "$JEU/$nom" >/dev/null 2>&1
        fi
    fi
}

echo "Rendu des tailles…"
rendre 16   icon_16x16.png
rendre 32   icon_16x16@2x.png
rendre 32   icon_32x32.png
rendre 64   icon_32x32@2x.png
rendre 128  icon_128x128.png
rendre 256  icon_128x128@2x.png
rendre 256  icon_256x256.png
rendre 512  icon_256x256@2x.png
rendre 512  icon_512x512.png
rendre 1024 icon_512x512@2x.png

if [ -z "$(ls -A "$JEU" 2>/dev/null)" ]; then
    echo "Erreur : aucun rendu produit." >&2
    echo "Installez rsvg-convert :  brew install librsvg" >&2
    exit 1
fi

mkdir -p "$RACINE/Ressources"
iconutil -c icns "$JEU" -o "$RACINE/Ressources/AVoixHaute.icns"

echo "Icône créée : Ressources/AVoixHaute.icns"
ls -lh "$RACINE/Ressources/AVoixHaute.icns" | awk '{print "  " $5}'

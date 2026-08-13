---
name: lire
description: Lit un texte à voix haute sur macOS, dans un lecteur audio flottant. À utiliser lorsque l'utilisateur demande d'écouter quelque chose, de lire à voix haute, de vocaliser un texte, ou dit qu'il préfère écouter plutôt que lire. Fonctionne avec la dernière réponse, un fichier, le presse-papiers ou un texte fourni.
---

# Lire à voix haute

La commande `lire` transmet du texte à l'application À Voix Haute, qui le
synthétise et l'ouvre dans un lecteur flottant. Le balisage Markdown est
retiré avant la lecture : ni croisillons, ni astérisques, ni URL prononcées.

## Utilisation

Lire la dernière réponse — transmettre le texte complet, sans le résumer :

```bash
cat <<'TEXTE' | lire
<le texte à lire>
TEXTE
```

Lire un fichier :

```bash
lire chemin/vers/document.md
```

Lire le presse-papiers :

```bash
pbpaste | lire
```

Arrêter toutes les lectures :

```bash
lire --stop
```

## À savoir

- L'application se lance d'elle-même si elle ne tourne pas.
- Le nettoyage du Markdown est fait par l'application : transmettre le texte
  brut, sans le préparer.
- Ne pas annoncer l'action avant de la faire ; confirmer en une ligne après.
- Si `lire` est introuvable, l'application À Voix Haute n'est pas installée,
  ou sa commande n'a pas été activée dans ses réglages.

Lit un texte à voix haute dans le lecteur flottant d'À Voix Haute.

Le Markdown est nettoyé avant la synthèse : ni croisillons, ni astérisques,
ni URL prononcées. Le lecteur reste au-dessus des autres fenêtres, même en
plein écran, et sa vitesse s'ajuste en cours d'écoute sans que la voix monte
dans les aigus.

## Comportement

Choisis la source selon ce que contient `$ARGUMENTS` :

**Sans argument** — lis ta dernière réponse, dans son intégralité et telle
que tu l'as écrite en Markdown :

```bash
cat <<'TEXTE' | lire
<ta dernière réponse>
TEXTE
```

**Un chemin de fichier** :

```bash
lire "$ARGUMENTS"
```

**`presse-papiers`** :

```bash
pbpaste | lire
```

**`stop`** :

```bash
lire --stop
```

**Tout autre texte** — lis-le directement :

```bash
cat <<'TEXTE' | lire
$ARGUMENTS
TEXTE
```

## Règles

- N'annonce pas ce que tu vas faire : lance la commande, puis confirme en
  une ligne.
- Pour ta dernière réponse, transmets le texte complet, sans le résumer.
  Le nettoyage du balisage est fait par l'application.
- Si `lire` est introuvable, indique que l'application À Voix Haute doit
  être installée, et sa commande activée dans ses réglages.

## Exemples

- `/lire` — écoute la dernière réponse
- `/lire README.md` — écoute un fichier
- `/lire presse-papiers` — écoute le presse-papiers
- `/lire stop` — arrête toutes les lectures

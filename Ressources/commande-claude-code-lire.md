Lit un texte à voix haute dans le lecteur flottant de Lecteur.app.

Le Markdown est nettoyé avant la synthèse : ni croisillons, ni astérisques, ni
URL prononcées. Le lecteur qui s'ouvre reste au-dessus des autres fenêtres, même
en plein écran, et permet d'ajuster la vitesse en cours d'écoute sans altérer la
hauteur de la voix.

## Comportement

Choisis la source selon ce que contient `$ARGUMENTS` :

**Sans argument** — lis ta dernière réponse. Reprends son texte intégral, tel que
tu l'as écrit en Markdown, et transmets-le :

```bash
cat <<'TEXTE' | lire
<ta dernière réponse, en Markdown brut>
TEXTE
```

**Un chemin de fichier** — lis ce fichier :

```bash
lire "$ARGUMENTS"
```

**`presse-papiers` ou `clipboard`** — lis le presse-papiers :

```bash
pbpaste | lire
```

**`stop`** — arrête toutes les lectures en cours :

```bash
lire --stop
```

**Tout autre texte** — lis ce texte directement :

```bash
cat <<'TEXTE' | lire
$ARGUMENTS
TEXTE
```

## Règles

- N'annonce pas ce que tu vas faire : lance la commande, puis confirme en une
  ligne (durée ou nombre de caractères transmis).
- Pour ta dernière réponse, transmets le texte **complet**, sans le résumer ni
  le reformuler. Le nettoyage du balisage est fait par l'application.
- Si `lire` est introuvable, indique la commande d'installation :
  `~/Projets/Lecteur/Scripts/installer_helper.sh`
- L'application se lance toute seule si elle ne tourne pas.

## Exemples

- `/lire` — écoute ma dernière réponse
- `/lire README.md` — écoute un fichier
- `/lire presse-papiers` — écoute le presse-papiers
- `/lire stop` — arrête tout
- `/lire Bonjour, ceci est un test` — écoute ce texte

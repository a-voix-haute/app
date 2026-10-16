# Moteur de synthèse distant

L'application sait appeler l'API de synthèse d'OpenAI en plus des voix
installées sur la machine. C'est le seul moteur à faire sortir le texte du
Mac : il est désactivé tant qu'aucune clé n'est enregistrée, et l'interface
le dit plutôt que de le supposer connu.

## Pourquoi un moteur distant

Les voix du système sont rattachées à une langue. Sur un texte mêlant deux
langues — « on a retiré `get-task-allow` du build » — `say` lit tout avec
l'accent français, y compris les identifiants techniques et les mots anglais.
Le résultat se comprend, mais s'écoute mal.

Les voix d'OpenAI sont multilingues : elles prononcent chaque passage avec
l'accent qui lui convient, sans qu'on ait à détecter la langue. C'est leur
seul véritable avantage sur les voix Premium d'Apple, et il porte précisément
sur les textes techniques.

## Mise en route

1. Créer une clé sur `platform.openai.com`, rubrique *API keys*
2. Réglages → **Cloud** → **+** → coller la clé, lui donner un nom
3. **Tester la clé** — un appel de deux mots valide la configuration
4. Réglages → **Voix** → choisir la voix cloud, écouter un extrait

Le moteur s'emploie ensuite de deux façons :

- **Moteur par défaut** : toutes les lectures passent par lui
- **Moteur secondaire** : le bouton ✨ du lecteur relit avec lui

Le second usage est le plus économe — on écoute couramment avec une voix
locale, et l'on reprend avec une meilleure voix les passages qui le méritent.

## Les clés

Elles sont conservées dans le **trousseau de macOS**, jamais dans les
préférences : une clé d'API ouvre un compte facturé, elle n'a pas sa place
dans un fichier lisible par n'importe quel processus de la session. Seul
l'index — identifiants et noms — vit dans `UserDefaults`, et il ne contient
rien d'exploitable.

Plusieurs clés peuvent coexister, chacune nommée. Le journal retient laquelle
a servi : c'est ce qui permet de rapprocher une consommation observée sur la
console du fournisseur d'un usage précis ici.

## Le journal des appels

`~/Library/Logs/AVoixHaute-api.log`, distinct du journal principal.

Chaque ligne porte la date, le nom de la clé, le modèle, la voix, le nombre
de caractères, la durée et l'issue. **Le texte envoyé n'y figure jamais** :
un journal qui conserverait les sélections de l'utilisateur annulerait la
protection des fichiers temporaires.

L'application **ne calcule aucun coût**. Les tarifs changent, et un montant
faux inspirerait moins confiance qu'un montant absent. Le montant facturé se
consulte sur la console du fournisseur ; le journal sert à savoir quelle clé
y correspond.

## Contraintes de l'API

**4096 caractères par requête.** Au-delà, le texte est découpé aux frontières
de phrase, chaque fragment synthétisé séparément, puis les flux MP3
concaténés — chaque trame MP3 porte son propre en-tête, et AVPlayer les lit à
la suite.

**Format `mp3`, jamais `aac`.** En AAC, l'API renvoie un flux ADTS brut, que
`AVPlayer` refuse de lire sous une extension `.m4a` — celle-ci annonce un
conteneur MPEG-4. Le lecteur s'ouvrait alors sans un son et sans erreur, ce
qui est le pire des échecs : silencieux. Le MP3 porte son format, extension
et contenu concordent.

**Vitesse entre 0,25 et 4.** Au-delà, la requête est refusée.

## En cas d'échec

Réseau coupé, clé refusée, quota atteint : l'erreur est signalée, **puis la
lecture repart avec le moteur local**. Sans ce repli, une panne de réseau
rendrait l'application muette — ce qu'aucun moteur optionnel ne devrait
provoquer.

## Points d'attention

**La détection de langue est court-circuitée** pour ce moteur. Ses voix ne se
rattachent à aucune langue (`langue == "mul"`), et en choisir une d'après la
langue détectée n'aurait pas de sens.

**`SecureField` refuse le collage** dans un `Form` macOS. Une clé d'API se
colle toujours, jamais ne se tape : la feuille de saisie emploie donc un
champ masqué par une bascule, doublé d'un bouton de collage explicite.

**Le bouton ✨ ouvre une nouvelle fenêtre.** Une synthèse ne peut reprendre
où la précédente en était — le découpage du texte ne correspond à aucune
position dans l'audio. La relecture repart du début, et les deux lecteurs
coexistent, ce qui permet de comparer.

# Migration de l'identifiant vers `app.avoixhaute.player`

**Appliquée en 2.0.0.** Ce document décrit ce qui a été fait, et pourquoi.

La migration transforme l'application en un logiciel *distinct* aux yeux de
macOS : l'autorisation Accessibilité, les préférences et l'agent de démarrage
sont tous indexés sur l'identifiant. Elle a été menée alors que l'application
n'avait pas d'utilisateur hors de son auteur — c'était le moment le moins
coûteux, et il ne se représentera pas.

## Pourquoi changer

`fr.dimitri.AVoixHaute` est un reverse-DNS d'un domaine personnel. Le projet vit
désormais sous l'organisation `a-voix-haute`, et l'identifiant désigne encore son
auteur plutôt que le projet. Le renommage précédent — « Lecteur » vers « À Voix
Haute » — a d'ailleurs laissé des `fr.dimitri.Lecteur.plist` derrière lui, ce qui
donne une idée de ce qu'une migration mal faite abandonne.

Rien n'est cassé aujourd'hui. C'est une question de cohérence, pas de
correction.

## Ce qui survit sans rien faire

Trois points souvent redoutés ne posent en réalité aucun problème.

| Élément | Pourquoi il survit |
|---|---|
| Service du clic droit | `NSPortName` suit le **nom de l'exécutable** (`AVoixHaute`), pas l'identifiant |
| Mise à jour intégrée | La signature est vérifiée sur l'**équipe** Developer ID (`5D6QHL72QC`), jamais sur l'identifiant |
| Signature et notarisation | Le certificat couvre l'équipe, pas un identifiant donné |
| Commandes `lire`, `read-aloud`… | Des liens symboliques vers un chemin, sans lien avec l'identifiant |

## Ce qui casse

| Élément | Conséquence | Réparable ? |
|---|---|---|
| **Autorisation Accessibilité** | Perdue. macOS voit une application inconnue | **Non** — l'utilisateur doit la réaccorder à la main |
| Préférences (`UserDefaults`) | Invisibles : le domaine change | Oui, par migration explicite |
| Agent de démarrage | Orphelin, pointant sur un `Label` disparu | Oui, à réécrire à l'installation |
| Schémas d'URL | Réenregistrés sous le nouvel identifiant | Oui, automatique |
| Répertoire temporaire | Change de nom, anciens fichiers orphelins | Oui, nettoyage |
| Sous-système du journal | Les anciens messages deviennent inaccessibles à `log stream` | Sans conséquence |

**L'autorisation Accessibilité est le point dur.** Aucune API ne permet de la
transférer — c'est une garantie de sécurité de macOS, pas une limitation
contournable. Tout utilisateur du raccourci global devra la réaccorder.

## Les 21 points d'ancrage

Répartis en trois familles, d'exigences très différentes.

### Structurants — changent l'identité du bundle

| Fichier | Ligne | Rôle |
|---|---|---|
| `Scripts/generer_projet.rb` | 21 | `IDENTIFIANT_APP`, source de vérité |
| `Sources/App/Info.plist` | 10 | `CFBundleIdentifier` |
| `Scripts/installer.sh` | 35, 84 | Chemin de l'agent, purge des préférences |
| `Scripts/installer.sh` | 162, 171 | `Label` et `-b` de l'agent de démarrage |

### Fonctionnels — cherchent l'application par son identifiant

| Fichier | Ligne | Rôle |
|---|---|---|
| `SourcesCLI/lire/main.swift` | 141 | `open -b` pour lancer l'application |
| `Sources/App/DelegueApplication.swift` | 83 | Repli de détection d'instance |
| `Sources/Commun/GestionnaireFichiersTemp.swift` | 14 | Nom du répertoire temporaire |

### Cosmétiques — sans effet fonctionnel

`Sources/Commun/Journal.swift` (sous-système, file d'écriture),
`Sources/Entree/ServeurSocket.swift` (label de file), `Sources/App/Info.plist`
(six `CFBundleURLName`), `Tests/ReglagesTests.swift` (domaine de test),
`Sources/Reglages/Reglages.swift` (un commentaire).

Le socket, lui, est indexé sur `AVoixHaute` et non sur l'identifiant : il n'est
pas concerné.

## Migration des préférences

Sans reprise explicite, l'utilisateur retrouve une application aux réglages
d'usine — voix, vitesse, raccourci, tout est perdu. Le principe :

C'est `Reglages.reprendreAncienDomaine()` qui s'en charge, appelée depuis
l'initialiseur.

Trois garde-fous comptent :

- **`stockage.object(forKey: cle) == nil`** ne réécrit jamais par-dessus un
  réglage déjà choisi ;
- **un drapeau** (`repriseAncienDomaineFaite`) évite qu'une reprise ne
  ressuscite un réglage que l'utilisateur vient de remettre par défaut ;
- **une liste blanche** de clés connues : `dictionaryRepresentation()` renvoie
  aussi les réglages globaux de macOS — langues, formats, accessibilité — dont
  la recopie polluerait le domaine de l'application.

L'ancien domaine n'est **pas** supprimé dans la foulée : un utilisateur qui
revient à une version antérieure y retrouve ses réglages. Une purge pourra venir
deux ou trois versions plus tard.

## Autorisation Accessibilité

Rien ne la transfère. Le seul travail possible était d'expliquer, plutôt que de
laisser un raccourci muet.

`installer.sh` détecte l'agent de démarrage de la 1.x — seule trace fiable
d'une installation précédente, le bundle ayant déjà été remplacé à ce stade —
et signale alors que l'autorisation est à réaccorder.

Le message est dans le script et non dans l'application : il paraît au moment
utile, sans interrompre l'utilisateur par une alerte au premier lancement. Il
n'est donc pas traduit, comme le reste des messages d'installation.

## Ce que la désinstallation reprend

`installer.sh --desinstaller` purge désormais **trois** domaines : le courant,
l'hérité, et `fr.dimitri.Lecteur` resté du renommage d'avant. Sans quoi la
migration aurait laissé les mêmes résidus que celle qui l'a précédée.

Un point mérite d'être noté au passage : la suite de tests crée un domaine par
exécution (`…tests.<UUID>`). Dix-huit fichiers s'étaient accumulés dans
`~/Library/Preferences` avant qu'on ne les remarque. Le motif les balaie
maintenant, pour les trois domaines.

`killall cfprefsd` suit la purge : le démon garde les préférences en mémoire et
réécrirait les fichiers qu'on vient de supprimer.

## Ce qui a été fait

1. `IDENTIFIANT_APP` dans le générateur, `CFBundleIdentifier` et les six
   `CFBundleURLName` dans l'`Info.plist`
2. Les trois points fonctionnels : `open -b` du helper, repli de détection
   d'instance, répertoire temporaire
3. `installer.sh` : agent renommé, ancien agent retiré à l'installation, purge
   des trois domaines — courant, hérité, et `fr.dimitri.Lecteur` resté du
   renommage précédent — plists de tests compris
4. Reprise des préférences dans `Reglages.swift`
5. Message d'installation signalant que l'autorisation est à réaccorder
6. Points cosmétiques : sous-système du journal, labels de files, domaine de test

## Un piège rencontré

La reprise doit précéder `register(defaults:)`, et non le suivre. Après
l'enregistrement des valeurs par défaut, `object(forKey:)` répond pour toute
clé pourvue d'un défaut : impossible alors de distinguer un réglage choisi par
l'utilisateur d'une valeur d'usine, et la reprise ne recopie plus rien.

Le symptôme est trompeur — seules passent les clés *sans* valeur par défaut,
`voixSay` et `voixAVSpeech`. Une reprise qui semble fonctionner, mais ne
transporte que deux réglages sur vingt.

## Vérifications passées

- Réglages de la 1.x simulés sur l'ancien domaine, puis installation : les
  quatre valeurs sont reprises (`vitesseParDefaut`, `voixSay`, `limiteLecteurs`,
  `raccourciGlobalActif`)
- Un réglage modifié après reprise, puis relance : la valeur de l'utilisateur
  tient, le drapeau empêche la reprise de se rejouer
- Canal URL et helper socket fonctionnels sous le nouvel identifiant
- Désinstallation : les deux domaines purgés, aucun résidu dans
  `~/Library/Preferences`
- 52 tests verts

## Reste à faire

L'ancien domaine `fr.dimitri.AVoixHaute` n'est pas supprimé après reprise : un
retour à une version antérieure doit y retrouver ses réglages. Une purge pourra
venir deux ou trois versions plus tard, en retirant `reprendreAncienDomaine()`
et la liste blanche qui l'accompagne.

<div align="center">

<img src="Documentation/images/logo.png" width="128" alt="À Voix Haute">

# À Voix Haute

**Écoutez n'importe quel texte, où qu'il se trouve.**

Application macOS native — Swift, AppKit et SwiftUI

[**Télécharger la dernière version**](https://github.com/dimer47/a-voix-haute/releases/latest)

</div>

---

## Le problème

macOS sait déjà lire une sélection à voix haute : c'est le raccourci
« Énoncer la sélection », Option + Échap par défaut. Il souffre d'un défaut
structurel : **la vitesse est fixée au moment de la synthèse**. Impossible de
l'ajuster une fois la lecture lancée, et accélérer dégrade la voix.

La mesure est sans appel. Sur une même phrase, en portant `say` de 175 à
437 mots par minute, la fréquence fondamentale passe de **76 Hz à 151 Hz** : la
voix double de hauteur. C'est l'effet « Mickey ».

À Voix Haute synthétise une seule fois, à vitesse nominale, puis applique
l'accélération **à la lecture** grâce à `AVPlayerItem.audioTimePitchAlgorithm`.
La fondamentale reste à 76 Hz, quelle que soit la vitesse choisie — de 0,5× à 3×,
ajustable en cours d'écoute.

## Ce que ça fait

- **Lecteur flottant** qui reste au-dessus des autres fenêtres, y compris
  par-dessus une application en plein écran, et suit l'utilisateur d'un bureau
  à l'autre
- **Vitesse ajustable en cours de lecture**, sans altérer la hauteur de la voix
- **Markdown nettoyé** avant la synthèse : titres, emphase, liens, tableaux et
  cases à cocher deviennent du texte qui s'écoute ; les blocs de code sont
  annoncés sans être lus
- **Plusieurs lectures simultanées**, avec des règles de coexistence
  configurables
- **Choix de la voix** parmi celles du système, triées par langue et par qualité

## Cinq façons de lancer une lecture

| Moyen | Usage |
|---|---|
| Clic droit | Sélection → Services → « Lire à voix haute » |
| Raccourci global | `⌃⌥L` sur une sélection, depuis n'importe quelle application |
| Barre de menus | L'icône en forme d'onde, pour lire le presse-papiers |
| Terminal | `pbpaste \| lire`, `lire document.md`, `lire --stop` |
| URL | `open "lire://presse-papiers"` |

## Assistants en ligne de commande

La commande s'installe en un clic dans douze assistants — Claude Code, Codex,
Cursor, Gemini CLI, Grok, OpenCode, Goose, Crush, Amp, GitHub Copilot, Aider,
Amazon Q — depuis les réglages, rubrique **Terminal**.

Selon la convention de chacun :

- ceux qui reconnaissent les commandes par barre oblique reçoivent un `/lire` ;
- ceux qui gèrent des compétences repèrent d'eux-mêmes qu'il faut lire : il
  suffit de le leur demander.

## Installation

### Depuis le disque d'installation

Ouvrez `À Voix Haute.dmg` et glissez l'application dans le dossier Applications.
L'application est signée et notarisée par Apple : elle s'ouvre sans avertissement.

### Depuis les sources

```bash
git clone <url-du-dépôt>
cd "À Voix Haute"
./Scripts/installer.sh
```

Le script compile, installe dans `/Applications`, lie la commande `lire` dans
`~/.local/bin`, enregistre le service macOS et active le lancement à l'ouverture
de session.

Pour tout retirer :

```bash
./Scripts/installer.sh --desinstaller
```

## Développement

### Prérequis

- macOS 14 ou supérieur — développé et testé sur macOS 26
- Xcode 26
- Le gem `xcodeproj` (`gem install xcodeproj`)

### Structure

Le projet Xcode est **généré par script** : `Scripts/generer_projet.rb` en est la
source de vérité. Les fichiers Swift ajoutés dans `Sources/` sont pris en compte
sans intervention dans Xcode.

```
Sources/
├── App/          point d'entrée, délégué, Info.plist
├── Synthese/     moteurs de synthèse, catalogue des voix
├── Lecture/      lecteur AVPlayer, gestionnaire multi-lecteur
├── Interface/    fenêtre flottante, réglages, assistant de configuration
├── Entree/       socket, service macOS, raccourci global, capture de sélection
├── Texte/        nettoyage Markdown, détection de langue
├── Integrations/ assistants en ligne de commande
├── Reglages/     préférences
└── Commun/       fichiers temporaires, journalisation
SourcesCLI/lire/  helper transmis à l'application par socket
```

### Scripts

| Script | Rôle |
|---|---|
| `generer_projet.rb` | Régénère le `.xcodeproj` |
| `construire.sh` | Compilation Release, `--distribuer` pour la signature Developer ID |
| `installer.sh` | Installation, démarrage automatique, `--desinstaller` |
| `notariser.sh` | Soumission à Apple et disque d'installation |
| `enregistrer_service.sh` | Rafraîchit le menu Services pendant le développement |
| `generer_icone.sh` | Produit l'icône depuis un tracé vectoriel |

### Tests

```bash
xcodebuild -project AVoixHaute.xcodeproj -scheme AVoixHauteTests test
```

## Choix techniques

**`AVPlayer` plutôt qu'`AVAudioPlayer`** — seul `AVPlayerItem` expose
`audioTimePitchAlgorithm`, indispensable pour préserver la hauteur de voix.
`AVAudioPlayer` a bien `enableRate`, mais pas le contrôle de l'algorithme.

**Socket de domaine Unix pour le helper** — les alternatives ont été écartées :
`NSDistributedNotificationCenter` abandonne silencieusement les grandes charges,
une URL corrompt les longs textes, XPC impose une signature. Le socket transmet
110 Ko sans altération, en 8 ms.

**`RegisterEventHotKey` (Carbon) pour le raccourci global** — c'est la seule
interface qui capte une combinaison sans autorisation préalable et qui consomme
l'événement, là où `NSEvent.addGlobalMonitorForEvents` le laisse aussi filer
vers l'application active.

**`say -f` avec un fichier temporaire** — le texte n'est jamais passé en
argument, ce qui supprime d'un coup l'échappement shell et la limite `ARG_MAX`.
`--data-format=aac` évite un AIFF intermédiaire de 140 Mo sur les longs textes.

**Bac à sable désactivé** — `Process`, le socket hors conteneur et `CGEventPost`
y sont incompatibles. L'application n'est pas destinée au Mac App Store.

## Limites connues

Les voix Siri (`com.apple.siri.*`) restent **inaccessibles** aux applications
tierces : macOS les réserve à ses propres services, quelle que soit la signature.
Les voix Premium et Améliorées, elles, sont utilisables une fois téléchargées
dans Réglages Système → Accessibilité → Contenu énoncé.

## Licence

Usage personnel.

# À Voix Haute — repères pour le développement

Application macOS de lecture audio. Swift, AppKit et SwiftUI, sans dépendance
externe.

## Compilation et installation

Le projet Xcode est **généré par script** : `Scripts/generer_projet.rb` en est la
source de vérité. Les fichiers Swift ajoutés dans `Sources/` sont pris en compte
automatiquement — ne jamais ajouter un fichier depuis Xcode, régénérer le projet.

```bash
ruby Scripts/generer_projet.rb      # après tout ajout ou suppression de fichier
./Scripts/construire.sh             # compilation Release
./Scripts/construire.sh --distribuer  # avec signature Developer ID
./Scripts/installer.sh              # installe dans /Applications
./Scripts/installer.sh --desinstaller
```

**Toujours réinstaller avant de demander une vérification à l'utilisateur.**
Compiler dans `build/` ne met pas à jour `/Applications`, et l'utilisateur
testerait une version périmée sans le savoir.

## Intégration continue

Deux workflows distincts, à ne pas confondre :

| Déclencheur | Workflow | Ce qu'il fait | Durée |
|---|---|---|---|
| Push sur `main` | `tests.yml` | Compilation Debug, 43 tests, vérification que Release compile | ~1 min |
| Push d'un tag `v*` | `release.yml` | Tests, signature, notarisation Apple, `.dmg`, release GitHub | ~3 min |

Un commit ordinaire ne produit **ni tag, ni dmg, ni release** — seulement les
tests. La notarisation sollicite les serveurs d'Apple, elle n'a pas sa place à
chaque commit.

```bash
git push                              # → tests
git tag v1.1.0 && git push origin v1.1.0   # → dmg notarisé + release
```

`tests.yml` porte `tags-ignore: ['**']` : sans cela, pousser un tag
déclencherait les deux workflows en parallèle et les tests tourneraient deux
fois.

La version de l'application dérive du tag, par `LECTEUR_VERSION` que le workflow
transmet au script de génération. Le workflow refuse de publier si la version
embarquée ne correspond pas au tag.

Les runners sont en `macos-26` : c'est la seule image dotée du SDK 26, que
`NSGlassEffectView` exige.

## Tests

```bash
xcodebuild -project AVoixHaute.xcodeproj -scheme AVoixHauteTests test
```

Sous test, l'application ne prend ni le socket, ni le service macOS, ni le
raccourci global : ces ressources sont uniques par utilisateur et appartiennent
à l'instance installée. La garde est `DelegueApplication.sousTest`.

## Contraintes à ne pas casser

**`AVPlayer`, jamais `AVAudioPlayer`** — seul `AVPlayerItem` expose
`audioTimePitchAlgorithm`, sans lequel la voix se déforme à vitesse élevée.
C'est la raison d'être du projet : `say -r` fait passer la fondamentale de
76 Hz à 151 Hz, notre lecteur la laisse inchangée.

**Sur `AVPlayer`, `rate == 0` signifie « en pause »** — ne jamais lire `rate`
pour connaître la vitesse. Le modèle conserve `vitesseSouhaitee` et utilise
`defaultRate`.

**Le texte passe par un fichier, jamais en argument de `say`** — cela supprime
l'échappement shell et la limite `ARG_MAX`. `--data-format=aac` évite un AIFF
intermédiaire de 140 Mo sur les longs textes.

**L'annulation coopérative de Swift ne traverse pas la frontière d'acteur**
entre le gestionnaire et le moteur : `MoteurSay` garde une prise directe sur ses
processus et les tue par `SIGTERM` puis `SIGKILL`.

**Le bac à sable reste désactivé** — `Process`, le socket hors conteneur et
`CGEventPost` y sont incompatibles. Le Mac App Store est donc exclu, ce qui est
assumé.

**`get-task-allow` doit être retiré avant notarisation** — Xcode l'ajoute
d'office en Release, et Apple rejette toute soumission qui le déclare. Le bundle
est resigné sans lui.

## Pièges rencontrés

**L'autorisation Accessibilité est attachée à l'emplacement du bundle** — une
copie lancée depuis `build/` n'hérite pas de l'autorisation accordée à celle de
`/Applications`. En développement, cela ressemble à une régression alors que
tout fonctionne.

**`os.Logger` ne restitue rien à la relecture** — les messages de niveau debug
et info sont absents de `log show`. Un journal de fichier existe en doublon :
`~/Library/Logs/AVoixHaute.log`, lisible par `tail -f`.

**Les scripts cherchent les processus par `pgrep -x AVoixHaute`** — le chemin
`/Applications/À Voix Haute.app` ne contient pas la chaîne « AVoixHaute.app »,
un motif fondé sur le chemin échouerait.

**Le nom porte deux formes** — « À Voix Haute » s'affiche, « AVoixHaute » sert
partout ailleurs : exécutable, identifiant, socket, journal, nom de port du
service. Ne pas introduire d'accent dans les chemins.

**Les voix Siri sont inaccessibles** aux applications tierces, quelle que soit
la signature. `say` accède en revanche aux voix Premium et Améliorées
téléchargées, que `AVSpeechSynthesisVoice` ne liste pas toutes.

## Langue

Tout est en français : code, commentaires, noms de symboles, messages de commit,
documentation. Les termes techniques gardent leur forme d'origine lorsqu'ils
désignent une API.

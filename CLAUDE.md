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

La version vient de `LECTEUR_VERSION`, que seul le workflow de publication
renseigne ; à défaut, elle dérive du dernier tag Git. Sans ce repli, une
compilation locale porterait 1.0.0 et proposerait une mise à jour à chaque
lancement.

**Le disque `.dmg` ne pose que le bundle.** Le service du clic droit, le
raccourci et les schémas d'URL s'en accommodent — ils sont déclarés dans
l'Info.plist ou enregistrés au lancement. La commande en ligne de commande et
le lancement à l'ouverture de session, eux, s'activent depuis Réglages →
Terminal → Installation (`InstallationSysteme`). Le script les met en place
lui-même, en déléguant à l'application pour l'ouverture de session : un agent
`launchd` et `SMAppService` ne se voient pas, et l'interrupteur des réglages
interroge le second.

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

**`@Observable` n'instrumente que les propriétés stockées** — les réglages sont
calculés au-dessus de `UserDefaults` : le macro n'a rien à réécrire, et SwiftUI
n'est jamais prévenu d'un changement. `Reglages` porte donc un compteur
`revision`, lu par chaque `get` et incrémenté par chaque `set`. Tout nouvel
accesseur doit appeler `signalerLecture()` et `signalerEcriture()`, sans quoi
une vue dépourvue d'autre état ne se redessinera pas.

Le symptôme trompe : une vue qui possède d'autres `@State` se rafraîchit par
ricochet et paraît fonctionner. Seule une vue sans état propre — une étape de
l'assistant de bienvenue, par exemple — révèle le défaut.

**Une vue affichant un état du disque doit le capturer** — `AssistantIA` est
`Identifiable` et son `id` ne change pas quand le fichier apparaît : `ForEach`
réutilise les lignes sans les redessiner. Capturer l'état dans un `@State` de
la vue, rafraîchi après chaque action, plutôt que de le relire à l'affichage.

**Le bac à sable reste désactivé** — `Process`, le socket hors conteneur et
`CGEventPost` y sont incompatibles. Le Mac App Store est donc exclu, ce qui est
assumé.

**`get-task-allow` doit être retiré, en distribution comme en local** — Xcode
l'ajoute d'office en Release. Apple rejette toute soumission qui le déclare,
mais la raison de fond est ailleurs : il autorise n'importe quel processus à
s'attacher au débogueur, donc à lire la mémoire de l'application — le texte en
cours de lecture compris. `construire.sh` resigne dans les deux branches, avec
le certificat Developer ID ou à défaut en ad hoc.

**Les fichiers temporaires portent le texte de l'utilisateur** — une sélection
prise dans n'importe quelle application, parfois un mot de passe. Dossier en
700, fichiers en 600 : `write(to:)` et `say` créent en 644, et le dossier
temporaire de macOS ne protège que parce que le système le veut bien.

## Pièges rencontrés

**`xcodebuild … test` compile en Debug dans le même `build/`** et laisse la
cible Release dans un état intermédiaire. Installer après les tests copierait
ce résultat partiel : réinstaller *après* les tests, jamais l'inverse. Devant un
comportement périmé inexplicable, `rm -rf build` tranche.

**Un heredoc non quoté est interprété par bash** — `<<PLIST` laissait les
accents graves d'un commentaire XML former une substitution de commande, et
`open -b` était réellement exécuté sans argument. Le fichier produit restait
correct, l'aide de `open` s'affichait au milieu de l'installation. `<<'PLIST'`
dès qu'aucune variable n'est à substituer.

**Un `grep` en fin de tube masque le code de retour** — `xcodebuild | grep …`
rend celui de `grep`. Sans test sur `${PIPESTATUS[0]}`, une compilation en échec
passe pour une réussite et l'installation copie le build précédent. De même,
`[ -d … ] && rm -rf …` s'évaluant à faux vaut un échec sous `set -e` et
interrompt le script.

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

**L'identifiant est `app.avoixhaute.player` depuis la 2.0.0** — l'ancien,
`fr.dimitri.AVoixHaute`, reste lu une fois par `Reglages` pour reprendre les
préférences, et purgé par la désinstallation. La reprise précède
`register(defaults:)` : après, `object(forKey:)` répond pour toute clé pourvue
d'un défaut, et l'on ne distingue plus un choix d'une valeur d'usine. Voir
`Documentation/migration-identifiant.md`.

**Un texte se traduit, un identifiant se décline** — la commande répond à six
noms, le schéma d'URL aussi, et `--stop` accepte quatre formes. Toutes restent
actives en permanence et ne suivent jamais la langue du système : une commande
notée dans un script doit fonctionner sur n'importe quelle machine. « read-aloud »
et non « read », qui est une primitive du shell et l'emporterait sur le lien.

Chaque schéma d'URL demande sa propre entrée `CFBundleURLTypes` : plusieurs
schémas dans une même entrée, et LaunchServices n'enregistre que le premier,
sans rien signaler.

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

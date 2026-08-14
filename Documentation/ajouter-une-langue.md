# Ajouter une langue

L'application est traduite en six langues : français — langue de développement —,
anglais, espagnol, allemand, italien et portugais. macOS choisit le catalogue
d'après les préférences de langue du système et retombe sur le français si
aucune ne correspond.

Ajouter une langue demande sept étapes, dont une seule est longue : la
traduction des 184 chaînes. Le reste est mécanique.

Ce guide prend le néerlandais (`nl`) en exemple. Remplacez ce code par le vôtre,
en respectant la norme ISO 639-1 attendue par macOS.

## Ce qui se traduit, et ce qui ne se traduit pas

La distinction gouverne tout le reste, et une erreur ici casse des choses qui
marchaient.

| Nature | Exemple | Traduire ? |
|---|---|---|
| Texte lu par un humain | « Fermer le lecteur à la fin de la lecture » | Oui |
| Nom de l'application | « À Voix Haute » | Non — c'est un nom propre |
| Identifiant tapé ou comparé | `--stop`, `lire://presse-papiers`, `lire` | Voir plus bas |

Les identifiants ne sont pas *traduits* mais **déclinés** : les formes s'ajoutent
sans que les anciennes disparaissent, et toutes restent actives en permanence.
Elles ne suivent jamais la langue du système — une commande notée dans un script
doit fonctionner sur toutes les machines, or un identifiant qui suivrait la
langue du poste casserait dès qu'il en change.

## 1. Créer le catalogue

```bash
cd "Ressources"
cp -R fr.lproj nl.lproj
```

Le dossier contient cinq fichiers :

| Fichier | Contenu | Volume |
|---|---|---|
| `Localizable.strings` | Interface : menus, réglages, alertes | 184 clés |
| `InfoPlist.strings` | Nom de l'app et entrée du menu Services | 3 clés |
| `commande-lire.md` | Notice de la commande, installée dans les assistants | ~60 lignes |
| `competence-lire.md` | Compétence installée dans les assistants | ~60 lignes |
| `LICENSE.txt` | Licence CC BY-NC-SA 4.0 | — |

## 2. Traduire `Localizable.strings`

Les 184 clés doivent toutes être présentes : une clé manquante fait afficher son
nom brut à l'écran — l'utilisateur lit `lecture.fermetureAuto` au lieu du texte.

Deux règles :

- **Les clés ne changent jamais.** Seule la valeur à droite du `=` se traduit.
- **Les paramètres se conservent.** `%d`, `%@` restent tels quels. Une traduction
  peut en changer l'ordre en les numérotant : `%1$@`, `%2$d`.

```
"lecture.fermetureAuto" = "Sluit de speler wanneer het afspelen eindigt";
"lecture.limite" = "Gelijktijdige spelers: %d";
```

Vérifiez l'alignement avec le français avant d'aller plus loin :

```bash
cd "Ressources"
diff <(grep -o '^"[^"]*"' fr.lproj/Localizable.strings | sort) \
     <(grep -o '^"[^"]*"' nl.lproj/Localizable.strings | sort)
```

Une sortie vide signifie que les deux catalogues portent exactement les mêmes
clés. Toute ligne affichée est une clé manquante ou en trop.

## 3. Traduire `InfoPlist.strings`

Trois clés, dont une seule se traduit :

```
"CFBundleDisplayName" = "À Voix Haute";
"CFBundleName" = "À Voix Haute";
"NSServices/0/NSMenuItem/default" = "Hardop voorlezen";
```

Le nom de l'application **reste identique dans toutes les langues** : c'est un
nom propre, au même titre que Firefox ou Photoshop. Seule
`NSServices/0/NSMenuItem/default` change — c'est l'entrée qui apparaît dans le
menu Services du clic droit.

## 4. Décliner les identifiants

Quatre endroits portent une liste en dur. Ils doivent rester cohérents entre
eux, faute de quoi une forme est acceptée d'un côté et rejetée de l'autre.

### a. Nom de la commande — `Scripts/installer.sh`

```sh
NOMS_HELPER=(lire read-aloud leer vorlesen leggi ler voorlezen)
```

Un lien symbolique par nom est créé dans `~/.local/bin`, tous pointant sur le
même binaire.

**Vérifiez que le nom n'est pas déjà pris**, en particulier par une primitive du
shell :

```bash
type voorlezen 2>/dev/null || echo "libre"
```

C'est pourquoi la forme anglaise est `read-aloud` et non `read` : `read` est une
primitive de bash et de zsh, et une primitive l'emporte toujours sur un fichier
du `PATH`. Le lien serait silencieusement sans effet — pire qu'absent.

### b. Schémas d'URL — deux endroits à modifier ensemble

Dans `Sources/App/Info.plist` :

```xml
<key>CFBundleURLSchemes</key>
<array>
    <string>lire</string>
    …
    <string>voorlezen</string>
</array>
```

Et dans `Sources/App/DelegueApplication.swift` :

```swift
private static let schemas: Set<String> = [
    "lire", "read-aloud", "leer", "vorlesen", "leggi", "ler", "voorlezen"
]
```

Les deux sont nécessaires et remplissent des rôles distincts : LaunchServices
n'achemine vers l'application que les schémas déclarés dans l'`Info.plist`, et le
code ne traite que ceux qu'il reconnaît. Oublier l'un des deux donne une URL qui
ouvre l'application sans rien faire, ou qui n'ouvre rien du tout.

### c. Hôtes d'URL — `Sources/App/DelegueApplication.swift`

```swift
private static let hotesPressePapiers: Set<String> = [
    "presse-papiers", "clipboard", …, "klembord"
]

private static let hotesTexte: Set<String> = [
    "texte", "text", "texto", "testo", "tekst"
]
```

### d. Options de la commande — `SourcesCLI/lire/main.swift`

```swift
case "--help", "-h", "--aide", …, "--hulp":
case "--stop", "-s", "--arreter", …, "--stoppen":
```

## 5. Traduire les messages de la commande

Le helper est une cible distincte du bundle : il n'a accès ni à
`Localizable.strings` ni à `tr()`, ses textes sont donc intégrés au code.

Dans `SourcesCLI/lire/main.swift`, ajoutez le code à la liste des langues
reconnues :

```swift
return ["fr", "en", "es", "de", "it", "pt", "nl"].contains(code) ? code : "fr"
```

Puis ajoutez un `case` dans chacun des sept messages de `enum Messages`, et un
dans le `switch` de `afficherAide()`. Le `default` reste le français.

## 6. Régénérer et compiler

Le générateur découvre les langues seul, par `Dir.glob` sur `Ressources/*.lproj`
— aucune liste à tenir à jour de ce côté. Il alimente `known_regions`, sans quoi
macOS n'annoncerait qu'une langue et ignorerait les autres catalogues, même
présents dans le bundle.

```bash
ruby Scripts/generer_projet.rb
./Scripts/installer.sh
```

La ligne `traductions : de, en, es, fr, it, nl, pt` confirme la prise en compte.

**Si un texte reste dans l'ancienne langue après installation**, le cache de
build a servi un artefact périmé :

```bash
rm -rf build
./Scripts/installer.sh
```

## 7. Vérifier

Comptez les clés dans l'application installée, et non dans les sources : c'est
le bundle qui sera exécuté.

```bash
for l in fr en es de it pt nl; do
  n=$(plutil -convert json -o - \
      "/Applications/À Voix Haute.app/Contents/Resources/$l.lproj/Localizable.strings" \
      2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  echo "$l : $n clés"
done
```

Les sept lignes doivent afficher le même nombre.

Notez que `grep` ne fonctionne pas sur ces fichiers une fois installés : ils sont
convertis en UTF-16 à la compilation. `plutil` est l'outil adapté.

Vérifiez ensuite les liens de la commande et les schémas d'URL :

```bash
ls -l ~/.local/bin | grep -E "voorlezen"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -dump | grep -c "bindings:.*voorlezen:"
```

### Tester le rendu réel

La seule vérification complète passe par une bascule de la langue du système,
dans Réglages Système → Langue et région. Elle affecte tout le Mac : ne la
laissez pas en place et rétablissez votre langue ensuite.

Ne modifiez pas `AppleLanguages` par `defaults write` pour ce test. La commande
écrit un réglage système global au lieu de rester dans un sous-processus, et une
variable d'environnement `AppleLanguages` n'influence pas
`Locale.preferredLanguages` sur macOS — le test paraît fonctionner sans rien
prouver.

## Récapitulatif des fichiers

| Fichier | Ce qu'on y fait |
|---|---|
| `Ressources/xx.lproj/Localizable.strings` | 184 chaînes d'interface |
| `Ressources/xx.lproj/InfoPlist.strings` | Entrée du menu Services |
| `Ressources/xx.lproj/*.md`, `LICENSE.txt` | Notices et licence |
| `Scripts/installer.sh` | `NOMS_HELPER` |
| `Sources/App/Info.plist` | `CFBundleURLSchemes` |
| `Sources/App/DelegueApplication.swift` | `schemas`, `hotesPressePapiers`, `hotesTexte` |
| `SourcesCLI/lire/main.swift` | Langue reconnue, `Messages`, `afficherAide()`, alias d'options |

Le projet Xcode n'est **pas** à modifier : il est généré par
`Scripts/generer_projet.rb`, qui est la source de vérité.

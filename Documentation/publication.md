# Publication d'une version

Deux chaînes coexistent : la publication automatique par GitHub Actions, et la
publication locale par `Scripts/notariser.sh`. La première demande une
configuration initiale, décrite ci-dessous ; la seconde fonctionne déjà.

## Publier une version

Une fois les secrets en place :

```bash
git tag v1.1.0
git push origin v1.1.0
```

Le workflow compile, lance les tests, signe, fait notariser par Apple, agrafe
le ticket, fabrique le disque et publie la release. Comptez une dizaine de
minutes, dont l'essentiel en attente de la notarisation.

## Configuration initiale

Trois secrets sont à créer une fois pour toutes dans le dépôt.

### 1. Exporter le certificat de signature

Le certificat Developer ID et sa clé privée doivent être exportés depuis le
trousseau, puis encodés en base64 pour transiter en tant que secret.

Dans **Trousseaux d'accès** :

1. Rubrique **Connexion**, catégorie **Mes certificats**
2. Repérer *Developer ID Application: …*
3. Clic droit → **Exporter…**, format *Échange d'informations personnelles
   (.p12)*
4. Choisir un mot de passe **non vide** et le noter : il devient le secret
   `CERTIFICAT_MOT_DE_PASSE`.

   Un `.p12` exporté sans mot de passe est refusé à l'import par macOS, avec
   un message trompeur — « passphrase you entered is not correct ».

Puis encoder le fichier :

```bash
base64 -i ~/Desktop/certificat.p12 -o /tmp/cert.b64
gh secret set CERTIFICAT_P12_BASE64 --repo dimer47/a-voix-haute < /tmp/cert.b64
rm /tmp/cert.b64
```

L'enregistrement se fait depuis un fichier plutôt que par un collage dans
l'invite : une saisie interactive peut aboutir à un secret vide sans que rien
ne le signale.

Supprimez le `.p12` du disque une fois l'opération faite : il contient votre clé
privée.

### 2. Créer un mot de passe d'application

Sur [account.apple.com](https://account.apple.com), rubrique **Connexion et
sécurité**, puis **Mots de passe des apps**. Le mot de passe obtenu — de la
forme `abcd-efgh-ijkl-mnop` — devient le secret `NOTARISATION_MOT_DE_PASSE`.

### 3. Enregistrer les secrets

```bash
gh secret set CERTIFICAT_P12_BASE64 --repo dimer47/a-voix-haute
gh secret set CERTIFICAT_MOT_DE_PASSE --repo dimer47/a-voix-haute
gh secret set NOTARISATION_MOT_DE_PASSE --repo dimer47/a-voix-haute
```

Chaque commande demande la valeur, sans l'afficher. Pour le premier secret,
collez le contenu produit à l'étape 1.

Vérification :

```bash
gh secret list --repo dimer47/a-voix-haute
```

## Ce que fait le workflow

| Étape | Détail |
|---|---|
| Import du certificat | Trousseau temporaire, détruit avec la machine virtuelle |
| Tests | Les mêmes que sur un poste de développement |
| Compilation | Release, runtime durci, droits déclarés |
| Resignature | Retire `get-task-allow`, qu'Apple refuse |
| Notarisation | Application, puis disque, avec agrafage du ticket |
| Publication | Release GitHub avec le `.dmg` en pièce jointe |

## Publication locale

Sans passer par GitHub, la chaîne complète tient en deux commandes :

```bash
./Scripts/construire.sh --distribuer
./Scripts/notariser.sh
```

Le disque est produit dans `build/distribution/`.

## En cas d'échec

**« Aucun certificat Developer ID trouvé »** — le `.p12` exporté ne contenait
pas la clé privée. Exportez-le depuis *Mes certificats*, pas depuis
*Certificats*.

**Notarisation refusée** — pour connaître le motif :

```bash
xcrun notarytool history --keychain-profile avoixhaute
xcrun notarytool log <identifiant> --keychain-profile avoixhaute
```

Les causes les plus fréquentes : `get-task-allow` présent, runtime durci absent,
ou un binaire embarqué non signé.

**Erreur 401 à l'enregistrement des identifiants** — le mot de passe utilisé
n'est pas un mot de passe d'application, ou l'identifiant Apple ne correspond
pas à l'équipe du certificat.

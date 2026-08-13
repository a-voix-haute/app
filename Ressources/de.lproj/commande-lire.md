Liest einen Text im schwebenden Player von À Voix Haute vor.

Markdown wird vor der Synthese entfernt: keine Rauten, keine Sternchen, keine
vorgelesenen Adressen. Der Player bleibt über den anderen Fenstern, auch im
Vollbild, und seine Geschwindigkeit lässt sich beim Hören anpassen, ohne dass die
Stimme höher wird.

## Verhalten

Wählen Sie die Quelle nach dem Inhalt von `$ARGUMENTS`:

**Ohne Argument** — lies deine letzte Antwort vollständig vor, genau so, wie du
sie in Markdown geschrieben hast:

```bash
cat <<'TEXT' | lire
<deine letzte Antwort>
TEXT
```

**Ein Dateipfad**:

```bash
lire "$ARGUMENTS"
```

**`zwischenablage`**:

```bash
pbpaste | lire
```

**`stop`**:

```bash
lire --stop
```

**Jeder andere Text** — lies ihn direkt vor:

```bash
cat <<'TEXT' | lire
$ARGUMENTS
TEXT
```

## Regeln

- Kündige nicht an, was du tun wirst: Führe den Befehl aus und bestätige in einer
  Zeile.
- Übergib bei deiner letzten Antwort den vollständigen Text, ohne ihn
  zusammenzufassen. Das Entfernen der Auszeichnung übernimmt die App.
- Wird `lire` nicht gefunden, weise darauf hin, dass À Voix Haute installiert und
  der Befehl in den Einstellungen aktiviert sein muss.

## Beispiele

- `/lire` — die letzte Antwort anhören
- `/lire README.md` — eine Datei anhören
- `/lire zwischenablage` — die Zwischenablage anhören
- `/lire stop` — alle Wiedergaben stoppen

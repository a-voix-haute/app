---
name: lire
description: Liest Text unter macOS in einem schwebenden Audioplayer vor. Zu verwenden, wenn der Nutzer bittet, etwas anzuhören, vorzulesen, einen Text zu vertonen, oder sagt, dass er lieber hört als liest. Funktioniert mit der letzten Antwort, einer Datei, der Zwischenablage oder einem übergebenen Text.
---

# Vorlesen

Der Befehl `lire` übergibt Text an die App À Voix Haute, die ihn synthetisiert und
in einem schwebenden Player öffnet. Markdown-Auszeichnung wird zuvor entfernt:
keine Rauten, keine Sternchen, keine vorgelesenen Adressen.

## Verwendung

Die letzte Antwort vorlesen — den vollständigen Text übergeben, ohne ihn zu
kürzen:

```bash
cat <<'TEXT' | lire
<der vorzulesende Text>
TEXT
```

Eine Datei vorlesen:

```bash
lire pfad/zum/dokument.md
```

Die Zwischenablage vorlesen:

```bash
pbpaste | lire
```

Alle Wiedergaben stoppen:

```bash
lire --stop
```

## Gut zu wissen

- Die App startet von selbst, wenn sie nicht läuft.
- Das Entfernen des Markdowns übernimmt die App: den Rohtext übergeben, ohne ihn
  aufzubereiten.
- Die Aktion nicht vorher ankündigen; danach in einer Zeile bestätigen.
- Wird `lire` nicht gefunden, ist À Voix Haute nicht installiert oder der Befehl
  wurde in den Einstellungen nicht aktiviert.

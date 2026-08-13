---
name: lire
description: Reads text aloud on macOS, in a floating audio player. Use it when the user asks to listen to something, to read aloud, to voice a text, or says they would rather listen than read. Works with the last reply, a file, the clipboard or a supplied text.
---

# Read aloud

The `lire` command hands text to the À Voix Haute application, which synthesises
it and opens it in a floating player. Markdown markup is stripped beforehand: no
hashes, no asterisks, no spoken URLs.

## Usage

Read the last reply — pass the complete text, without summarising it:

```bash
cat <<'TEXT' | lire
<the text to read>
TEXT
```

Read a file:

```bash
lire path/to/document.md
```

Read the clipboard:

```bash
pbpaste | lire
```

Stop all playback:

```bash
lire --stop
```

## Worth knowing

- The application starts itself if it is not running.
- Stripping the Markdown is the application's job: pass the raw text, without
  preparing it.
- Do not announce the action before performing it; confirm in one line
  afterwards.
- If `lire` is not found, À Voix Haute is not installed, or its command has not
  been enabled in its settings.

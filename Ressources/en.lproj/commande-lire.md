Reads text aloud in À Voix Haute's floating player.

Markdown is stripped before synthesis: no hashes, no asterisks, no spoken URLs.
The player stays above other windows, even in full screen, and its speed can be
adjusted while listening without the voice rising in pitch.

## Behaviour

Choose the source according to what `$ARGUMENTS` contains:

**No argument** — read your last reply, in full and exactly as you wrote it in
Markdown:

```bash
cat <<'TEXT' | lire
<your last reply>
TEXT
```

**A file path**:

```bash
lire "$ARGUMENTS"
```

**`clipboard`**:

```bash
pbpaste | lire
```

**`stop`**:

```bash
lire --stop
```

**Any other text** — read it directly:

```bash
cat <<'TEXT' | lire
$ARGUMENTS
TEXT
```

## Rules

- Do not announce what you are about to do: run the command, then confirm in one
  line.
- For your last reply, pass the complete text without summarising it. Stripping
  the markup is the application's job.
- If `lire` is not found, say that À Voix Haute must be installed and its command
  enabled in its settings.

## Examples

- `/lire` — listen to the last reply
- `/lire README.md` — listen to a file
- `/lire clipboard` — listen to the clipboard
- `/lire stop` — stop all playback

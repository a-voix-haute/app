Legge un testo ad alta voce nel lettore fluttuante di À Voix Haute.

Il Markdown viene ripulito prima della sintesi: niente cancelletti, niente
asterischi, niente indirizzi pronunciati. Il lettore resta sopra le altre
finestre, anche a schermo intero, e la sua velocità si regola durante l'ascolto
senza che la voce salga di tono.

## Comportamento

Scegli la fonte in base al contenuto di `$ARGUMENTS`:

**Senza argomento** — leggi la tua ultima risposta, per intero e così come l'hai
scritta in Markdown:

```bash
cat <<'TESTO' | lire
<la tua ultima risposta>
TESTO
```

**Un percorso di file**:

```bash
lire "$ARGUMENTS"
```

**`appunti`**:

```bash
pbpaste | lire
```

**`stop`**:

```bash
lire --stop
```

**Qualsiasi altro testo** — leggilo direttamente:

```bash
cat <<'TESTO' | lire
$ARGUMENTS
TESTO
```

## Regole

- Non annunciare ciò che stai per fare: esegui il comando, poi conferma in una
  riga.
- Per la tua ultima risposta, trasmetti il testo completo, senza riassumerlo.
  La pulizia della formattazione spetta all'applicazione.
- Se `lire` non si trova, indica che À Voix Haute va installata e il suo comando
  attivato nelle impostazioni.

## Esempi

- `/lire` — ascoltare l'ultima risposta
- `/lire README.md` — ascoltare un file
- `/lire appunti` — ascoltare gli appunti
- `/lire stop` — interrompere tutte le letture

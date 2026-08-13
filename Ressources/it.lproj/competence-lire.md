---
name: lire
description: Legge un testo ad alta voce su macOS, in un lettore audio fluttuante. Da usare quando l'utente chiede di ascoltare qualcosa, di leggere ad alta voce, di vocalizzare un testo, o dice che preferisce ascoltare piuttosto che leggere. Funziona con l'ultima risposta, un file, gli appunti o un testo fornito.
---

# Leggere ad alta voce

Il comando `lire` consegna il testo all'applicazione À Voix Haute, che lo
sintetizza e lo apre in un lettore fluttuante. La formattazione Markdown viene
rimossa prima: niente cancelletti, niente asterischi, niente indirizzi
pronunciati.

## Uso

Leggere l'ultima risposta — trasmettere il testo completo, senza riassumerlo:

```bash
cat <<'TESTO' | lire
<il testo da leggere>
TESTO
```

Leggere un file:

```bash
lire percorso/al/documento.md
```

Leggere gli appunti:

```bash
pbpaste | lire
```

Interrompere tutte le letture:

```bash
lire --stop
```

## Da sapere

- L'applicazione si avvia da sola se non è in esecuzione.
- La pulizia del Markdown spetta all'applicazione: trasmettere il testo grezzo,
  senza prepararlo.
- Non annunciare l'azione prima di compierla; confermare in una riga dopo.
- Se `lire` non si trova, À Voix Haute non è installata, oppure il suo comando
  non è stato attivato nelle impostazioni.

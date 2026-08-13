Lê um texto em voz alta no leitor flutuante do À Voix Haute.

O Markdown é limpo antes da síntese: sem cardinais, sem asteriscos, sem endereços
pronunciados. O leitor permanece sobre as outras janelas, mesmo em ecrã inteiro, e
a sua velocidade ajusta-se durante a audição sem que a voz suba de tom.

## Comportamento

Escolhe a origem conforme o conteúdo de `$ARGUMENTS`:

**Sem argumento** — lê a tua última resposta, na íntegra e tal como a escreveste
em Markdown:

```bash
cat <<'TEXTO' | lire
<a tua última resposta>
TEXTO
```

**Um caminho de ficheiro**:

```bash
lire "$ARGUMENTS"
```

**`area-de-transferencia`**:

```bash
pbpaste | lire
```

**`stop`**:

```bash
lire --stop
```

**Qualquer outro texto** — lê-o diretamente:

```bash
cat <<'TEXTO' | lire
$ARGUMENTS
TEXTO
```

## Regras

- Não anuncies o que vais fazer: executa o comando e confirma numa linha.
- Para a tua última resposta, transmite o texto completo, sem o resumir. A limpeza
  da marcação cabe à aplicação.
- Se `lire` não for encontrado, indica que o À Voix Haute tem de estar instalado e
  o seu comando ativado nas definições.

## Exemplos

- `/lire` — ouvir a última resposta
- `/lire README.md` — ouvir um ficheiro
- `/lire area-de-transferencia` — ouvir a área de transferência
- `/lire stop` — parar todas as leituras

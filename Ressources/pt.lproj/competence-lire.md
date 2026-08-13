---
name: lire
description: Lê um texto em voz alta no macOS, num leitor de áudio flutuante. A usar quando o utilizador pede para ouvir algo, para ler em voz alta, para vocalizar um texto, ou diz que prefere ouvir a ler. Funciona com a última resposta, um ficheiro, a área de transferência ou um texto fornecido.
---

# Ler em voz alta

O comando `lire` entrega o texto à aplicação À Voix Haute, que o sintetiza e o
abre num leitor flutuante. A marcação Markdown é limpa antes: sem cardinais, sem
asteriscos, sem endereços pronunciados.

## Utilização

Ler a última resposta — transmitir o texto completo, sem o resumir:

```bash
cat <<'TEXTO' | lire
<o texto a ler>
TEXTO
```

Ler um ficheiro:

```bash
lire caminho/para/documento.md
```

Ler a área de transferência:

```bash
pbpaste | lire
```

Parar todas as leituras:

```bash
lire --stop
```

## A saber

- A aplicação inicia-se sozinha se não estiver em execução.
- A limpeza do Markdown cabe à aplicação: transmitir o texto em bruto, sem o
  preparar.
- Não anunciar a ação antes de a fazer; confirmar numa linha depois.
- Se `lire` não for encontrado, o À Voix Haute não está instalado, ou o seu
  comando não foi ativado nas definições.

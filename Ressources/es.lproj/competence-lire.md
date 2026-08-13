---
name: lire
description: Lee un texto en voz alta en macOS, en un reproductor de audio flotante. Úsala cuando el usuario pida escuchar algo, leer en voz alta, vocalizar un texto, o diga que prefiere escuchar antes que leer. Funciona con la última respuesta, un archivo, el portapapeles o un texto facilitado.
---

# Leer en voz alta

El comando `lire` entrega el texto a la aplicación À Voix Haute, que lo sintetiza
y lo abre en un reproductor flotante. El marcado Markdown se limpia antes: sin
almohadillas, sin asteriscos, sin direcciones pronunciadas.

## Uso

Leer la última respuesta — transmitir el texto completo, sin resumirlo:

```bash
cat <<'TEXTO' | lire
<el texto que leer>
TEXTO
```

Leer un archivo:

```bash
lire ruta/al/documento.md
```

Leer el portapapeles:

```bash
pbpaste | lire
```

Detener todas las lecturas:

```bash
lire --stop
```

## Conviene saber

- La aplicación se inicia sola si no está en ejecución.
- La limpieza del Markdown corre a cargo de la aplicación: transmita el texto en
  bruto, sin prepararlo.
- No anuncie la acción antes de realizarla; confirme en una línea después.
- Si no encuentra `lire`, À Voix Haute no está instalada, o su comando no se ha
  activado en los ajustes.

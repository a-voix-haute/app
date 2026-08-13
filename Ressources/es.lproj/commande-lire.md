Lee un texto en voz alta en el reproductor flotante de À Voix Haute.

El Markdown se limpia antes de la síntesis: sin almohadillas, sin asteriscos, sin
direcciones pronunciadas. El reproductor permanece sobre las demás ventanas,
incluso en pantalla completa, y su velocidad se ajusta durante la escucha sin que
la voz suba de tono.

## Comportamiento

Elija la fuente según lo que contenga `$ARGUMENTS`:

**Sin argumento** — lea su última respuesta, íntegra y tal como la escribió en
Markdown:

```bash
cat <<'TEXTO' | lire
<su última respuesta>
TEXTO
```

**Una ruta de archivo**:

```bash
lire "$ARGUMENTS"
```

**`portapapeles`**:

```bash
pbpaste | lire
```

**`stop`**:

```bash
lire --stop
```

**Cualquier otro texto** — léalo directamente:

```bash
cat <<'TEXTO' | lire
$ARGUMENTS
TEXTO
```

## Reglas

- No anuncie lo que va a hacer: ejecute el comando y confirme en una línea.
- Para su última respuesta, transmita el texto completo, sin resumirlo. La
  limpieza del marcado corre a cargo de la aplicación.
- Si no encuentra `lire`, indique que hay que instalar À Voix Haute y activar su
  comando en los ajustes.

## Ejemplos

- `/lire` — escuchar la última respuesta
- `/lire README.md` — escuchar un archivo
- `/lire portapapeles` — escuchar el portapapeles
- `/lire stop` — detener todas las lecturas

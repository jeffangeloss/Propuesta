# Especificación de telemetría

Un archivo CSV por bloque de juego, en `~/Documents/fnf-telemetria/`.

Se escribe **fuera del build** a propósito: el `.app` se regenera en cada compilación y borraría
los datos. Se hace `flush` en cada evento, así que un cierre forzado no cuesta la sesión — solo
las marcas de cierre.

**Nombre:** `<participante>_<condicion>_<cancion>_<AAAAMMDD-HHMMSS>.csv`

---

## Cabecera

Líneas iniciadas con `#`. En pandas: `pd.read_csv(archivo, comment='#')`.

```
# participante=P01
# condicion=adaptativa
# cancion=Bopeebo
# dificultad=Normal
# playback_rate=1
# rating_offset_ms=0
# note_offset_ms=0
# ventana_sick_ms=45
# ventana_good_ms=90
# ventana_bad_ms=135
# modo_experimento=1
# piso_de_vida=0.025
# umbral_recuperacion=0.15
# ghost_tapping_efectivo=0
```

Cada archivo declara **bajo qué reglas fue generado**. Sin esto, un bloque sin ningún `miss_press`
es indistinguible de uno donde el ghost tapping estaba activo, y un bloque sin `failure_threshold`
es indistinguible de uno donde el piso de vida ocultó los cruces.

Los offsets de calibración son críticos: si cambian entre sesiones y no quedaron registrados,
los errores de timing dejan de ser comparables y no hay forma de recuperarlo después.

La última línea del archivo lleva el resumen del bloque:

```
# resumen aciertos=59 errores=69 score=14760 precision=0.370703125
```

---

## Columnas

| Columna | Tipo | Descripción |
|---|---|---|
| `seq` | int | Secuencia dentro del bloque, desde 1 |
| `unix_ms` | float | Reloj de pared, epoch en ms. **Sincronización con biometría** |
| `song_time_ms` | float | Posición en la canción. **Segmentación musical** |
| `evento` | str | Ver tabla de eventos |
| `direccion` | int | Carril 0–3; `-1` en eventos sin carril |
| `juicio` | str | `sick`, `good`, `bad`, `shit`; vacío si no aplica |
| `timing_error_ms` | float | Con signo. Vacío si no aplica |
| `combo` | int | Combo después del evento |
| `score` | int | Puntaje acumulado |
| `health` | float | Vida, rango 0–2 |
| `sustain` | 0/1 | En `miss`, 1 marca el fallo de la cabeza de una nota larga. En `hit` vale 0, porque el motor no juzga las piezas de las notas largas |
| `version` | str | Versión del chart **de la nota** (`facil`, `media`, `dificil`). Vacío si el intercambio está apagado |
| `segmento` | int | Segmento de 8 compases al que pertenece la nota. Vacío si el intercambio está apagado |
| `nota_ms` | float | Momento en que la nota debía tocarse, en ms de canción (incluye `note_offset_ms`) |
| `detalle` | str | Datos de los eventos `decision` y `cuadro_largo`, como `clave=valor` separados por `;` |

### Los dos relojes

`unix_ms` y `song_time_ms` avanzan juntos mientras la partida corre. **La deriva medida es de
~27 ms sobre 82 s de juego (0,03 %)**, suficiente para alinear ventanas biométricas con eventos
del juego sin corrección.

Una pausa rompe esa correspondencia: el reloj de pared sigue y el tiempo de canción se congela.
Por eso en modo experimento la pausa está bloqueada, y si igual ocurre queda registrada.

### Convención de signo de `timing_error_ms`

```
negativo = el jugador respondió ADELANTADO
positivo = el jugador respondió ATRASADO
```

Es la convención estándar en la literatura de sincronización sensoriomotora, donde la
**asincronía negativa media** (la tendencia humana a anticiparse levemente al pulso) es un
hallazgo clásico. El engine calcula este valor con `Math.abs()` y descarta el signo; aquí se
captura antes.

Una media significativamente negativa es evidencia de que el instrumento mide sincronización
real y no solo aciertos.

---

## Eventos

| Evento | Cuándo |
|---|---|
| `block_start` | Inicio del bloque. Primera fila |
| `hit` | Nota acertada. Único con `juicio` y `timing_error_ms` |
| `miss` | Nota que pasó sin ser tocada |
| `miss_press` | Tecla pulsada sin nota que acertar. Solo si el ghost tapping está desactivado |
| `failure_threshold` | **Entrada** al estado de fracaso (vida ≤ 0). Solo en modo experimento |
| `failure_recovered` | **Salida** del estado de fracaso (vida > umbral de recuperación) |
| `pause` | Partida pausada. No debería aparecer en modo experimento |
| `resume` | Partida reanudada. Solo se emite si hubo un `pause` previo |
| `block_end` | Fin del bloque. Ausente si la sesión se interrumpió |
| `decision` | Intercambio: el segmento siguiente entra a la fila de aparición. `version` y `segmento` son los del segmento que entra |
| `chart_cut` | Intercambio: la canción cruza un corte. `version` es la que empieza a sonar |
| `cuadro_largo` | Un cuadro duró más de 33 ms. `detalle` lleva `duracion_ms` |

En las filas `hit`, `health` es el valor **en el instante del juicio**, antes de aplicar la
ganancia de vida de esa misma nota.

En las filas `failure_threshold`, `health` es el valor **antes** de aplicar el piso, así que
puede ser ≤ 0. Registra la profundidad del cruce.

---

## Intercambio de versiones del chart

Se activa en modo experimento, o con `intercambio=1` en `sesion.txt`. La canción necesita sus
tres charts (`<cancion>-easy`, `<cancion>`, `<cancion>-hard`) y hay que elegir la dificultad
Normal, porque la Media es el chart maestro: rival, eventos, cámara y velocidad salen de ella.

Un corte cae al inicio de cada grupo de 8 secciones. Unos 2,25 s antes de cada corte (el plazo),
el juego lee `decision.json` de la carpeta de telemetría, elige la versión del segmento siguiente
y lo agrega a la fila de aparición antes de que alguna de sus notas llegue a la pantalla.

```json
{"bloque": "P01_adaptativa_roses_20260922-150000", "segmento": 3, "decision": "sube",
 "seq": 17, "fuente": "simulado", "unix_ms": 1790108400123}
```

La decisión solo vale si `bloque` es el nombre del CSV en curso y `segmento` es el que entra.
Si no, o si el archivo falta, la versión se mantiene y la fila `decision` dice
`recibida=sin_decision`. Con `condicion=estatica` el juego toca Media siempre y registra la
decisión sin aplicarla (`aplicada=0`).

Cabecera que agrega el intercambio:

```
# modo_chart=intercambio
# aplica_decisiones=1
# version_inicial=media
# compases_por_corte=8
# cortes_ms=0;16000;32000;48000;64000;80000
# plazos_ms=0;13750;29750;45750;61750;77750
# aparicion_ms=2000
# margen_ms=250
# velocidad=1.3
# huella_facil=<sha256 del chart>
# huella_media=<sha256 del chart>
# huella_dificil=<sha256 del chart>
```

`detalle` de cada fila `decision`: `recibida`, `fuente`, `seq`, `margen_ms` (tiempo que faltaba
para que la primera nota del segmento pudiera aparecer; negativo = entrega tarde) y `aplicada`.

Si la canción no cumple (falta un chart, BPM distinto, una nota larga cruza un corte o hay un
evento Change Scroll Speed), la cabecera dice `modo_chart=fijo` con `error_intercambio=<motivo>`.
En modo experimento, además, el bloque no empieza y el juego muestra el motivo.

Claves de `sesion.txt` para pruebas: `intercambio=1` activa el intercambio sin modo experimento y
`prueba_auto=1` registra la telemetría también con Botplay.

---

## Variables derivadas por bloque

```python
import pandas as pd

df = pd.read_csv(archivo, comment='#')
hits = df[df.evento == 'hit']

# --- Precisión temporal ---
error_medio   = hits.timing_error_ms.mean()      # signo = sesgo de anticipación/retraso
error_abs     = hits.timing_error_ms.abs().mean()  # magnitud del error
variabilidad  = hits.timing_error_ms.std()       # consistencia rítmica

# --- Desempeño ---
n_hits    = len(hits)
n_miss    = (df.evento == 'miss').sum()
n_press   = (df.evento == 'miss_press').sum()    # pulsaciones espurias
combo_max = df.combo.max()
precision = n_hits / (n_hits + n_miss)
dist_juicios = hits.juicio.value_counts(normalize=True)

# --- Estado de fracaso ---
entradas = df[df.evento == 'failure_threshold'].song_time_ms.values
salidas  = df[df.evento == 'failure_recovered'].song_time_ms.values
fin      = df.song_time_ms.max()

n_episodios = len(entradas)
if len(salidas) < len(entradas):       # seguía en fracaso al terminar
    salidas = list(salidas) + [fin]
tiempo_fracaso = sum(s - e for e, s in zip(entradas, salidas))
pct_fracaso    = 100 * tiempo_fracaso / fin
```

### Sobre la histéresis

`failure_threshold` marca solo la **entrada** al estado de fracaso. Mientras el jugador sigue
en el suelo, la vida se mantiene en el piso sin generar eventos nuevos; hace falta recuperarse
por encima del umbral para que un cruce posterior cuente como episodio distinto.

Sin esa histéresis el conteo es ruido: como el daño por fallo (0,05) supera al piso (0,025),
cada tecla pulsada estando en el suelo generaría un evento. En una prueba real esto produjo
**45 eventos para 3 episodios**.

**`pct_fracaso` es la variable más útil de este grupo**: es continua, por tanto más potente
estadísticamente que un conteo, y es una medida objetiva de dificultad experimentada,
independiente del autorreporte de la Flow Short Scale. Sirve como evidencia convergente por
una vía distinta.

---

## Verificación de integridad

Antes de analizar un bloque:

| Comprobación | Criterio |
|---|---|
| Bloque completo | Existe una fila `block_end` |
| Sin huecos de reloj | `pause` y `resume` en cantidades iguales; idealmente cero |
| Signo preservado | `timing_error_ms` tiene valores positivos **y** negativos |
| Juicios coherentes | `max(abs(error))` por juicio no supera su ventana declarada en la cabecera |
| Configuración correcta | `modo_experimento=1` y `condicion` es la esperada para ese bloque |
| Charts correctos | `modo_chart=intercambio` y las tres `huella_*` coinciden con las del validador de charts |
| Intercambio correcto | `verificar_intercambio.py` (repositorio FNF Motiv, carpeta `bio/`) pasa todas sus revisiones |

La cuarta comprobación es la que detecta desalineaciones entre la telemetría y el motor de
juicio. En las pruebas de validación: `sick` máx. 43 ms (ventana 45), `good` máx. 89 ms
(ventana 90) — ningún evento fuera de su umbral.

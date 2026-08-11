# Modo experimento

Se activa con `experimento=1` en `~/Documents/fnf-telemetria/sesion.txt`.

**Los tres cambios que introduce alteran la tarea que enfrenta el participante y deben estar
escritos en la sección de método de la tesis.** No son detalles de implementación.

---

## 1. La pausa queda bloqueada

Durante la partida, la tecla de pausa no hace nada.

**Por qué.** Las muestras biométricas llevan marca de reloj de pared y los eventos del juego van
en tiempo de canción. Una pausa congela el segundo y no el primero, creando un hueco
irrecuperable entre ambos. En una prueba real, una pausa de 3,4 minutos produjo un desfase de
**202 segundos** entre los dos relojes.

Un participante que pausa sin que quede registrado inutiliza el bloque, y en el análisis no hay
forma de darse cuenta.

Independientemente del código, pausar durante un bloque permitiría descansar, romper el flow y
alterar la percepción de dificultad. En un experimento no debería ser posible.

**Complemento fuera del código:** perder el foco de la ventana (notificación, Cmd+Tab, clic
fuera) puede alterar el estado del juego aunque la pausa esté bloqueada. Durante las sesiones:
modo No Molestar activado, pantalla completa, nada más abierto en la máquina.

---

## 2. Ghost tapping desactivado

Las teclas pulsadas cuando no hay nota que acertar se registran como `miss_press` y descuentan
vida. Con la configuración por defecto del engine (`ghostTapping = true`) esas pulsaciones se
descartan sin dejar rastro.

**Por qué.** Presionar sin nota es un indicador real de desempeño —pérdida del seguimiento
rítmico, impulsividad— y es plausible que distinga a participantes con y sin formación musical.
Descartarlo es perder datos.

**Nota de implementación.** El engine bloquea el ghost tapping en **dos** lugares: `keyPressed()`
decide si `noteMissPress()` llega a llamarse, y esa función tiene además su propia verificación.
Parchear solo una deja el comportamiento sin cambios, y la cabecera del CSV reporta
`ghost_tapping_efectivo=0` mientras los datos siguen sin registrarse. Es un fallo silencioso.

No se modifica `ClientPrefs`: la condición se evalúa en el punto de uso, de modo que las
preferencias guardadas del juego quedan intactas.

---

## 3. La vida tiene piso y el participante no puede morir

La vida no baja de `0.025`. El bloque siempre corre completo. Los cruces del umbral se registran
como `failure_threshold` / `failure_recovered`.

### Por qué

- **Duración de bloque igual entre condiciones.** Si el participante muere, el bloque termina
  antes y la exposición deja de ser comparable, que es la base del diseño intra-sujeto.
- **La frecuencia de muerte sería un confusor.** Es plausible que se muera más en la condición
  estática que en la adaptativa, precisamente porque el sistema adaptativo evita el fracaso. Eso
  haría que la duración del bloque dependa de la condición.
- **Ventanas biométricas completas.** El RMSSD necesita al menos 60 s continuos, idealmente 2
  minutos. Una muerte a los 40 s deja el bloque sin ventana utilizable.
- **Mejor dato, no menos.** La vida se sigue registrando como variable continua, y los pares
  entrada/salida dan número de episodios de fracaso y porcentaje del bloque en ese estado. Ambas
  son más informativas que un evento binario de muerte.

### ⚠️ Al participante no se le informa

La barra de vida se sigue drenando y se sigue viendo vacía, así que la amenaza percibida se
mantiene intacta.

**Es deliberado.** Anunciar que no se puede perder reduciría las consecuencias percibidas, y el
flow depende de que el desafío importe — es la variable dependiente principal del estudio.
Informarlo contaminaría exactamente lo que se quiere medir.

**Esto es una omisión deliberada de información sobre la tarea y debe estar declarada en:**

1. La solicitud al comité de ética institucional.
2. El guion de debriefing, donde se le explica al participante al terminar la sesión.

Es una práctica estándar y menor en psicología experimental. Declarada se aprueba sin
dificultad; omitida es un problema serio.

---

## Verificación antes de cada sesión

| Comprobación | Cómo |
|---|---|
| Modo experimento activo | La cabecera del CSV dice `modo_experimento=1` |
| Identificación correcta | `participante` y `condicion` corresponden al bloque |
| Sin canciones del juego base | El build de sesiones se compila **sin** `-DBASE_GAME_FILES` |
| Audio calibrado | Offset verificado en esa máquina y esa salida de audio |
| Salida con cable | Nunca Bluetooth: 100–300 ms de latencia variable |
| Máquina aislada | No Molestar, pantalla completa, nada más abierto |

**Después de cada bloque**, confirmar que el CSV tiene `block_end` y cero filas `pause`. Si falta
el cierre o aparece una pausa, el bloque está comprometido y conviene anotarlo antes de seguir.

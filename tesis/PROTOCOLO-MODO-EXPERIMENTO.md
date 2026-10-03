# Modo experimento

Se activa con `experimento=1` en `~/Documents/fnf-telemetria/sesion.txt`.

**Los cuatro cambios que introduce alteran la tarea que enfrenta el participante y deben estar
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

## 4. Solo las cuatro flechas juegan las notas

Todos los participantes juegan con ← ↓ ↑ → y con la mano derecha. A, S, W y D, que el motor trae
como teclas alternas, y cualquier otra tecla no disparan notas ni cuentan como `miss_press`. El
mando tampoco juega.

**Por qué.** Decisión del 3 de octubre de 2026. La mano izquierda descansa quieta sobre la mesa
con los sensores biométricos (el MAX30102 en la yema del índice, los electrodos del GSR y la IMU en
el dorso). Una letra pulsada por esa mano, o rozada, no puede dejar en el CSV un acierto ni un
`miss_press` ajenos a la tarea.

**Nota de implementación.** No se modifica `ClientPrefs` ni el archivo de controles. Psych Engine
guarda los controles del menú de opciones en `controls_v3.sol`, dentro del perfil de Windows de
quien abre el juego (`C:\Users\<usuario>\AppData\Roaming\ShadowMario\PsychEngine\`), y al arrancar
esos controles reemplazan a los de fábrica. Cambiar los valores por defecto no bastaría, porque la
PC del IA LAB jugaría con lo que alguien haya guardado en ese perfil. En modo experimento
`PlayState` toma el carril de una tabla fija (`source/backend/TeclasExperimento.hx`) y no consulta
los controles guardados, igual que con el ghost tapping. Fuera del modo experimento el juego sigue
usando los controles del menú.

El motor lee las teclas de nota en tres lugares, que son `onKeyPress()` al pulsar,
`onKeyRelease()` al soltar y `keysCheck()` mientras se sostiene una nota larga. Si se parchea solo
el primero, una letra sigue sosteniendo las notas largas. Es otro fallo silencioso.

### Otras teclas que no hacen nada durante el bloque

| Tecla | Fuera del modo experimento | En modo experimento |
|---|---|---|
| R | Baja la vida a cero | Nada. Con el piso de vida registraría un `failure_threshold` que el participante no causó |
| 7 y 8 | Abren el editor de charts y el de personajes | Nada. Cortarían el bloque a la mitad |
| 1 y 2 (solo en el build de depuración) | Terminan la canción o la adelantan 10 s | Nada |
| Enter y Esc (pausa) | Pausan | Nada (sección 1) |

Las teclas de los menús (A, S, W y D además de las flechas, Ctrl, Espacio y Enter en Freeplay)
siguen activas, porque el investigador maneja los menús. Durante el bloque ninguna tiene
efecto, ya que la pausa y el game over no se abren. Las teclas de volumen (0, - y +) también siguen
activas, lejos de la mano izquierda.

**Complemento fuera del código.** La tecla Windows y Alt+Tab sacan el foco de la ventana, y el
juego no puede bloquearlas. La mano izquierda descansa lejos del teclado y, si el teclado tiene
bloqueo de la tecla Windows (modo juego), conviene activarlo.

---

## Verificación antes de cada sesión

| Comprobación | Cómo |
|---|---|
| Modo experimento activo | La cabecera del CSV dice `modo_experimento=1` |
| Solo flechas | En una canción de prueba con `experimento=1`, A, S, W y D no iluminan ninguna flecha del jugador y ← ↓ ↑ → sí |
| Identificación correcta | `participante` y `condicion` corresponden al bloque |
| Sin canciones del juego base | El build de sesiones se compila **sin** `-DBASE_GAME_FILES` |
| Audio calibrado | Offset verificado en esa máquina y esa salida de audio |
| Salida con cable | Nunca Bluetooth: 100–300 ms de latencia variable |
| Máquina aislada | No Molestar, pantalla completa, nada más abierto |

**Después de cada bloque**, confirmar que el CSV tiene `block_end` y cero filas `pause`. Si falta
el cierre o aparece una pausa, el bloque está comprometido y conviene anotarlo antes de seguir.

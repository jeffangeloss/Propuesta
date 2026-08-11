# Estado del proyecto

Se actualiza al cerrar cada hito.

**Última actualización:** 11 de agosto de 2026 — cierre del Hito 1.

---

## Diseño vigente

Diseño factorial mixto 2 × 2: **formación musical** (entre-sujetos, medida como variable
continua) × **condición adaptativa/estática** (intra-sujeto, contrabalanceada).

| | Hipótesis |
|---|---|
| H1 | El flow autorreportado es mayor en la condición adaptativa que en la estática |
| H2 | Bajo condición estática, los participantes con formación musical tienen mayor precisión rítmica *(verifica la premisa del diseño)* |
| **H3** | **La diferencia de flow entre grupos es menor en la condición adaptativa que en la estática** *(hipótesis central)* |
| H4 | La magnitud del ajuste aplicado por el controlador difiere según formación musical *(verifica el mecanismo)* |

**Plan por etapas.** Seminario I: piloto con n≈12–16 y DDA **por reglas**, para estimar el
tamaño del efecto y validar el protocolo. Seminario II: muestra dimensionada, modelo entrenado
con los datos del piloto, y un tercer brazo (DDA solo por telemetría de desempeño) que permita
aislar el aporte específico de la biometría.

> El orden importa: no se puede entrenar el modelo sin datos etiquetados, ni obtener datos sin
> correr sesiones. Por eso el modelo entrenado no puede estar en Seminario I.

⚠️ Este diseño está **pendiente de aprobación del asesor**. Todo lo construido hasta ahora lo
asume, pero no altera el instrumento: la telemetría es la misma con cualquier encuadre.

---

## Hito 1 — Telemetría · TERMINADO

Psych Engine 1.0.4 compilando nativo en arm64 y registrando siete tipos de evento por bloque.

- Error de timing **con signo**, capturado antes del `Math.abs()` del engine
- Modo experimento configurable desde `sesion.txt` sin recompilar
- Verificado jugando: juicios coherentes con sus ventanas, pares de eventos balanceados,
  bloques completos

**Deriva medida entre reloj de pared y tiempo de canción: ~27 ms sobre 82 s (0,03 %).** Este es
el número que hace viable sincronizar ventanas biométricas con eventos del juego.

Documentación: [README.md](README.md) · [ESPECIFICACION-TELEMETRIA.md](ESPECIFICACION-TELEMETRIA.md) · [PROTOCOLO-MODO-EXPERIMENTO.md](PROTOCOLO-MODO-EXPERIMENTO.md)

### Fallos silenciosos encontrados durante la validación

Los tres habrían llegado a los datos sin dar ninguna señal, y se habrían descubierto en el
análisis con las sesiones ya hechas:

| Hallazgo | Consecuencia si no se detecta |
|---|---|
| El ghost tapping está bloqueado en **dos** lugares del engine | La cabecera reporta `ghost_tapping_efectivo=0` mientras los datos no se registran |
| Cerrar el game over dispara `closeSubState()` y emitía un `resume` sin `pause` | Descuadra la reconstrucción del desfase de relojes |
| Sin histéresis, cada tecla en el suelo contaba como cruce del umbral | 45 eventos para 3 episodios reales |

---

## Bloqueado por terceros — máxima prioridad

Nada de esto avanza escribiendo código, y todo tiene semanas de demora:

- [ ] **Documento de ajuste de diseño al asesor.** Redactado y sin enviar. Bloquea el diseño.
- [ ] **Comité de ética.** El mayor riesgo de cronograma. Debe cubrir el registro de señales
      fisiológicas, el consentimiento informado y **la omisión sobre el piso de vida**
      (ver [PROTOCOLO-MODO-EXPERIMENTO.md](PROTOCOLO-MODO-EXPERIMENTO.md)).
- [ ] **Sensor GSR.** No se consigue localmente. Pedir por importación (3–6 semanas) y armar el
      DIY mientras tanto.
- [ ] **Asesor externo** del laboratorio: formalizar o descartar.

## Hardware

| Componente | Estado |
|---|---|
| MPU-6050 (IMU) | ✅ Canal de artefactos y marcador de sincronía |
| AD8232 (ECG) | ✅ Mejor que el MAX30102 planeado: electrodos al torso, manos libres de artefacto |
| Módulo "MH-ET LIVE" | ❓ Sin identificar — puede ser el MAX30102 o la placa ESP32 |
| Sensor GSR | ❌ **Falta.** Señal principal de activación |

---

## Hitos siguientes

### Hito 2 — Nodo ESP32 y sincronización

Firmware con ECG a 250–500 Hz y GSR a 20 Hz, publicando por MQTT en lotes. Suscriptor en Python
que estampa las muestras al llegar.

> ⚠️ Ambas señales analógicas deben ir a pines del **ADC1 (GPIO 32–39)**. El ADC2 no funciona
> con el WiFi activo: las lecturas funcionan perfecto en pruebas de banco y mueren al conectar
> MQTT, lo que hace buscar el error en el lugar equivocado.

**El entregable real es la validación de sincronía:** tres golpecitos secos al sensor IMU al
inicio y al final de cada bloque. El juego registra las marcas de bloque, el IMU registra los
picos, y la correlación da el desfase real y la deriva. Cero hardware extra.

### Hito 3 — Controlador adaptativo

Basado en reglas, con umbrales declarados, ajustando velocidad de notas, ventanas de juicio y
drenaje de vida — los tres parámetros modificables en runtime sin alterar el chart. Debe
**registrar cada ajuste con marca de tiempo**: ese log es el dato de H4.

Canal de control: Python escribe `params.json`, el juego lo lee cada N frames. Latencia ~100 ms,
suficiente, y sin riesgo de red.

### Hito 4 — Charts propios

Material de entrenamiento rítmico (subdivisiones, síncopas, cambios de tempo), **de 2 minutos o
más** cada uno para que las ventanas de RMSSD sean utilizables. Reemplazan a las canciones del
juego base y eliminan el confusor de familiaridad previa.

### Después

Ensayo interno con 3–4 personas para depurar el protocolo → piloto (n≈12–16, reclutando en ambos
extremos del espectro de formación musical) → análisis, estimación de dz y dimensionamiento en
G*Power con el procedimiento *ANOVA: repeated measures, within-between interaction*.

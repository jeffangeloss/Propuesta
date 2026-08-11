# Captura biométrica

Tubería ESP32 → MQTT → CSV, con el análisis de sincronía contra la telemetría del juego.

```
simulador.py  ──┐
                ├──► mosquitto ──► suscriptor.py ──► ~/Documents/fnf-telemetria/bio/
firmware ESP32 ─┘                                            │
                                                             ▼
                                                       sincronia.py
                                                             ▲
                              telemetría del juego (unix_ms) ┘
```

## Instalación

```bash
brew install mosquitto
python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
```

## Prueba sin hardware

```bash
./prueba_tuberia.sh 120        # 120 segundos
./prueba_tuberia.sh 60 5       # 60 segundos con 5% de pérdida simulada
```

Levanta el broker, corre el suscriptor y el simulador, y reporta. **Si esto falla, no tiene
sentido conectar sensores**: depurar la tubería con cables de por medio es mucho más lento.

## Sesión real

```bash
mosquitto -c mosquitto.conf -v                                   # terminal 1
./.venv/bin/python suscriptor.py --participante P01 --condicion adaptativa   # terminal 2
```

Al terminar el bloque:

```bash
./.venv/bin/python sincronia.py ~/Documents/fnf-telemetria/bio/P01_adaptativa_<sello>/ \
    --juego ~/Documents/fnf-telemetria/P01_adaptativa_<cancion>_<sello>.csv
```

---

## Protocolo MQTT

Tópicos `tesis/bio/imu`, `tesis/bio/ecg`, `tesis/bio/gsr`. Payload JSON con lotes:

```json
{"seq": 42, "t_us": 1234567, "dt_us": 4000, "v": [2048, 2051, ...]}
```

| Campo | Significado |
|---|---|
| `seq` | Contador de mensajes. **Un salto = lote perdido = hueco real en la señal** |
| `t_us` | `micros()` del ESP32 para la PRIMERA muestra del lote |
| `dt_us` | Intervalo entre muestras |
| `v` / `ax`,`ay`,`az` | Arreglos paralelos de valores |

**Nunca un mensaje por muestra.** A 250 Hz serían 250 mensajes por segundo y el broker se
satura. Los lotes de 50 muestras bajan eso a 5 mensajes por segundo sin perder resolución
temporal, porque el espaciado lo reconstruye `dt_us`.

**`seq` no es opcional.** Sin él, un lote perdido produce una serie que *parece* continua y
no lo es. El suscriptor lo cuenta y avisa.

---

## Los dos relojes

| Reloj | Bueno para | Malo para |
|---|---|---|
| `esp_us` — `micros()` del ESP32 | Espaciado entre muestras | Cero arbitrario, cristal con deriva |
| `llegada_ms` — reloj de pared del PC | Anclaje absoluto; **es el mismo reloj que `unix_ms` del juego** | Trae el jitter del WiFi |

Se guardan los dos crudos. `sincronia.py` los combina después; convertir en caliente metería
el jitter dentro de los datos sin posibilidad de deshacerlo.

### Por qué el ajuste no es por mínimos cuadrados simple

La latencia de red es **siempre positiva**: un lote puede llegar tarde, nunca temprano. El
error no está centrado en cero y un ajuste ordinario queda sesgado hacia las llegadas lentas.

La relación verdadera está en la **envolvente inferior** — los lotes que llegaron con la
mínima latencia. `sincronia.py` ajusta iterativamente sobre el cuartil de menor residuo.

### ⚠️ La ventana de estimación importa mucho

Validado contra una deriva conocida de +200 ppm inyectada por el simulador:

| Ventana | Deriva estimada | Error |
|---|---|---|
| 12 s | +175 ppm | 12,5 % |
| 120 s | **+201,7 ppm** | **0,85 %** |

**Ajustar siempre sobre el bloque completo, nunca sobre ventanas cortas.** En 12 segundos,
200 ppm son apenas 2,4 ms de desplazamiento total — indistinguible del jitter. En 2 minutos
son 24 ms, perfectamente estimables.

Ese mismo número es la razón de hacer la corrección: **ignorar la deriva cuesta ~24 ms
acumulados en un bloque de 2 minutos.**

---

## Golpes de sincronía

Tres golpecitos secos al sensor IMU al **inicio** y al **final** de cada bloque. El juego
registra sus marcas `block_start` / `block_end` con `unix_ms`; el IMU registra los picos.
La diferencia entre ambos es el desfase real de la cadena completa.

Cero hardware adicional, y da un número reportable en el método.

`sincronia.py` los detecta por umbral sobre la magnitud de aceleración, con período
refractario, y los agrupa. Si un grupo no tiene exactamente 3 golpes, avisa.

**Precisión limitada por la frecuencia del IMU:** a 50 Hz, la resolución es de 20 ms. Si hace
falta más, subir la tasa del IMU — pero 20 ms ya es holgado frente a las ventanas de EDA
(segundos) y de HRV (≥60 s).

---

## Pines del ESP32

Placa verificada: **ESP32-D0WD-V3 rev 3.1** (módulo WROOM-32), 4 MB de flash.

> ⚠️ **El ADC2 no funciona con el WiFi activo.** Las señales analógicas van obligatoriamente
> a pines del **ADC1: GPIO 32, 33, 34, 35, 36, 39**. Los cuatro últimos son solo-entrada, lo
> que los hace ideales para sensores. Si se conectan al ADC2, las lecturas funcionan perfecto
> en pruebas de banco y mueren al conectar MQTT — y el error aparenta ser del sensor.

| Señal | Pin sugerido | Tasa |
|---|---|---|
| ECG (AD8232) | GPIO 34 (ADC1, solo entrada) | 250–500 Hz |
| GSR | GPIO 35 (ADC1, solo entrada) | 20 Hz |
| IMU (MPU-6050) | GPIO 21 SDA / 22 SCL (I2C) | 50 Hz |

El IMU es I2C, así que no compite por el ADC.

---

## Archivos

| Archivo | Qué hace |
|---|---|
| `mosquitto.conf` | Broker abierto a la red local (mosquitto 2.x lo exige explícitamente) |
| `suscriptor.py` | MQTT → CSV por canal, con detección de lotes perdidos |
| `simulador.py` | ESP32 falso con deriva y golpes; valida la tubería sin hardware |
| `sincronia.py` | Mapeo de relojes y detección de golpes |
| `prueba_tuberia.sh` | Prueba de humo completa |

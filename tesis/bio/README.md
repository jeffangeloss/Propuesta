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

## Firmware

Placa verificada: **ESP32-D0WD-V3 rev 3.1** (módulo WROOM-32), 4 MB de flash, en
`/dev/cu.usbserial-110`.

```bash
cp firmware/credenciales.ejemplo.h firmware/credenciales.h   # y editarlo
ipconfig getifaddr en0                                       # IP de la Mac, para MQTT_HOST

arduino-cli compile --fqbn esp32:esp32:esp32 firmware
arduino-cli upload  --fqbn esp32:esp32:esp32 -p /dev/cu.usbserial-110 firmware
arduino-cli monitor -p /dev/cu.usbserial-110 --config baudrate=115200
```

`credenciales.h` está en `.gitignore`: **la clave del WiFi no debe subirse a un repo público.**

> ⚠️ **Compilar en Mac con Apple Silicon requiere dos cosas.**
>
> arduino-cli preprocesa los `.ino` con `ctags` para insertar prototipos, y ese binario viene
> compilado solo para Intel (`bad CPU type in executable`). Se invoca siempre, aunque el
> sketch sea trivial.
>
> **1.** Reemplazar el binario por universal-ctags, que sí es arm64 y acepta los mismos flags:
> ```bash
> brew install universal-ctags
> C=~/Library/Arduino15/packages/builtin/tools/ctags/5.8-arduino11/ctags
> mv "$C" "$C.x86_backup" && ln -sf /opt/homebrew/bin/ctags "$C"
> ```
>
> **2.** Mantener el código fuera del `.ino`. universal-ctags genera un formato ligeramente
> distinto al de la versión parcheada por Arduino, y los prototipos terminan insertados
> **dentro** de los cuerpos de las funciones. Los archivos `.cpp` de la carpeta del sketch se
> compilan tal cual, sin preprocesar. Por eso `firmware.ino` solo contiene `setup()` y
> `loop()` —que ya están declarados en `Arduino.h`— y todo lo demás vive en `nodo.cpp`.
>
> Las dos hacen falta: con solo la primera, los prototipos se insertan mal; con solo la
> segunda, ctags ni siquiera arranca.

---

## Pines

> ⚠️ **El ADC2 no funciona con el WiFi activo.** Las señales analógicas van obligatoriamente
> a pines del **ADC1: GPIO 32, 33, 34, 35, 36, 39**. Los cuatro últimos son solo-entrada, lo
> que los hace ideales para sensores. Si se conectan al ADC2, las lecturas funcionan perfecto
> en pruebas de banco y mueren al conectar MQTT — y el error aparenta ser del sensor.
>
> Ojo: la restricción es solo para lectura **analógica**. Usar un pin del ADC2 como entrada o
> salida digital no tiene problema, y por eso los pines de leads-off del AD8232 pueden ir ahí.

### MPU-6050 / GY-521 — conectado ahora

| Módulo | ESP32 | Nota |
|---|---|---|
| VCC | 3.3V | El módulo acepta 3–5 V, pero con 3.3 V el bus I2C queda al nivel del ESP32 |
| GND | GND | |
| SCL | GPIO 22 | I2C, con pull-ups en el propio módulo |
| SDA | GPIO 21 | |
| ADD | *sin conectar* | Selección de dirección. Flotante o a GND → `0x68`. A 3.3 V → `0x69` |
| INT | *sin conectar* | El firmware muestrea por temporizador, no por interrupción |
| XDA | *sin conectar* | I2C auxiliar, solo para encadenar un magnetómetro |
| XCL | *sin conectar* | |

Cuatro cables. Si el firmware reporta que el MPU no responde, lo primero es probar la
dirección `0x69` en `nodo.cpp`.

### AD8232 (ECG) — hito 2d

| Módulo | ESP32 | Nota |
|---|---|---|
| 3.3V | 3.3V | |
| GND | GND | |
| OUTPUT | **GPIO 34** | ADC1, solo entrada |
| LO+ | GPIO 25 | Detección de electrodo suelto (digital, ADC2 no molesta) |
| LO− | GPIO 26 | |
| SDN | *sin conectar* | |

A 250–500 Hz. Hace falta `analogSetPinAttenuation(34, ADC_11db)` para leer el rango completo
de 0–3.3 V: por defecto el ADC del ESP32 solo cubre hasta ~1.1 V y la señal se recorta arriba.

**Electrodos:** RA y LA bajo las clavículas, referencia en la costilla inferior izquierda. Las
muñecas no sirven — vuelven a meter artefacto de movimiento por el tecleo.

### GSR — hito 2e

| Módulo | ESP32 |
|---|---|
| VCC | 3.3V |
| GND | GND |
| Señal | **GPIO 35** (ADC1, solo entrada) |

A 20 Hz, con la misma atenuación. Electrodos en la eminencia hipotenar (base de la palma) o
en la planta del pie: los dedos están ocupados tecleando.

### LED de estado

GPIO 2, el LED integrado de la placa. Parpadeo rápido = conectando; encendido fijo =
publicando. Durante una sesión se está atendiendo al participante, no mirando una terminal.

---

## Archivos

| Archivo | Qué hace |
|---|---|
| `mosquitto.conf` | Broker abierto a la red local (mosquitto 2.x lo exige explícitamente) |
| `suscriptor.py` | MQTT → CSV por canal, con detección de lotes perdidos |
| `simulador.py` | ESP32 falso con deriva y golpes; valida la tubería sin hardware |
| `sincronia.py` | Mapeo de relojes y detección de golpes |
| `prueba_tuberia.sh` | Prueba de humo completa |

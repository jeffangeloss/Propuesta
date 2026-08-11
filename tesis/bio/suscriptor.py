#!/usr/bin/env python3
"""
Suscriptor MQTT de señales biométricas.

Recibe lotes de muestras del ESP32, los expande a muestras individuales y escribe un CSV
por canal en ~/Documents/fnf-telemetria/bio/.

DOS RELOJES
-----------
  esp_us         reloj monotónico del ESP32 (micros()). Preciso para el espaciado entre
                 muestras, pero su cero es arbitrario y su cristal deriva.
  llegada_ms     reloj de pared del PC al recibir el mensaje. Es el MISMO reloj que usa la
                 telemetría del juego (columna unix_ms), pero trae el jitter del WiFi.

Se guardan los dos. El mapeo esp_us -> unix_ms se ajusta después con `sincronia.py`, que
usa una recta robusta: el espaciado lo da el ESP32 y el anclaje absoluto, las llegadas.
Convertir en caliente metería el jitter de WiFi dentro de los datos sin posibilidad de
deshacerlo.

PÉRDIDA DE MENSAJES
-------------------
Cada mensaje lleva `seq`. Un salto significa lote perdido, o sea un hueco real en la señal.
Se cuenta y se avisa: sin esto la serie parece continua cuando no lo es.

Uso:
    ./.venv/bin/python suscriptor.py --participante P01 --condicion adaptativa
"""

import argparse
import csv
import json
import os
import signal
import sys
import time
from datetime import datetime

import paho.mqtt.client as mqtt

BASE = os.path.expanduser("~/Documents/fnf-telemetria/bio")
TOPICO = "tesis/bio/#"

# Canales esperados por tópico. El ESP32 manda arreglos paralelos con estos nombres.
CANALES = {
    "imu": ["ax", "ay", "az"],
    "ecg": ["v"],
    "gsr": ["v"],
}


class Canal:
    """Un CSV por tipo de señal, con su contador de secuencia."""

    def __init__(self, nombre, columnas, directorio, meta):
        self.nombre = nombre
        self.columnas = columnas
        self.ruta = os.path.join(directorio, f"{nombre}.csv")
        self.n_muestras = 0
        self.n_mensajes = 0
        self.n_perdidos = 0
        self.ultimo_seq = None

        self.f = open(self.ruta, "w", newline="")
        for k, v in meta.items():
            self.f.write(f"# {k}={v}\n")
        self.f.write(f"# canal={nombre}\n")
        self.f.write("# esp_us: reloj monotonico del ESP32. llegada_ms: reloj de pared del PC.\n")
        self.f.write("# El mapeo entre ambos lo hace sincronia.py; aqui se guardan crudos.\n")
        self.w = csv.writer(self.f)
        self.w.writerow(["esp_us", "llegada_ms", "msg_seq"] + columnas)

    def agregar(self, payload, llegada_ms):
        seq = payload.get("seq")
        if self.ultimo_seq is not None and seq is not None:
            faltan = seq - self.ultimo_seq - 1
            if faltan > 0:
                self.n_perdidos += faltan
                print(f"  [!] {self.nombre}: {faltan} lote(s) perdido(s) antes de seq={seq}")
        self.ultimo_seq = seq
        self.n_mensajes += 1

        t0 = payload["t_us"]
        dt = payload["dt_us"]
        series = [payload[c] for c in self.columnas]
        n = min(len(s) for s in series)

        for i in range(n):
            self.w.writerow([t0 + i * dt, f"{llegada_ms:.3f}", seq] + [s[i] for s in series])
        self.n_muestras += n

    def cerrar(self):
        self.f.flush()
        self.f.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--participante", default="test")
    ap.add_argument("--condicion", default="estatica")
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--puerto", type=int, default=1883)
    args = ap.parse_args()

    sello = datetime.now().strftime("%Y%m%d-%H%M%S")
    directorio = os.path.join(BASE, f"{args.participante}_{args.condicion}_{sello}")
    os.makedirs(directorio, exist_ok=True)

    meta = {
        "participante": args.participante,
        "condicion": args.condicion,
        "inicio_unix_ms": f"{time.time() * 1000:.3f}",
        "inicio_local": datetime.now().isoformat(timespec="seconds"),
    }

    canales = {}
    print(f"Escribiendo en {directorio}")
    print(f"Broker {args.host}:{args.puerto}, topico {TOPICO}")
    print("Ctrl-C para cerrar.\n")

    def on_connect(client, userdata, flags, rc, properties=None):
        if rc == 0:
            client.subscribe(TOPICO, qos=0)
            print("Conectado al broker. Esperando muestras...")
        else:
            print(f"[!] Fallo de conexion, codigo {rc}")

    def on_message(client, userdata, msg):
        # Se estampa ANTES de parsear: el tiempo de parseo no debe contaminar la marca.
        llegada_ms = time.time() * 1000
        nombre = msg.topic.rsplit("/", 1)[-1]
        columnas = CANALES.get(nombre)
        if columnas is None:
            return
        try:
            payload = json.loads(msg.payload)
        except (ValueError, UnicodeDecodeError) as e:
            print(f"  [!] payload ilegible en {msg.topic}: {e}")
            return
        if nombre not in canales:
            canales[nombre] = Canal(nombre, columnas, directorio, meta)
            print(f"  + canal {nombre}")
        try:
            canales[nombre].agregar(payload, llegada_ms)
        except (KeyError, TypeError) as e:
            print(f"  [!] lote mal formado en {nombre}: {e}")

    cliente = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    cliente.on_connect = on_connect
    cliente.on_message = on_message

    try:
        cliente.connect(args.host, args.puerto, keepalive=30)
    except OSError as e:
        print(f"[!] No se pudo conectar al broker: {e}")
        print("    ¿Esta corriendo?  mosquitto -c tesis/bio/mosquitto.conf -v")
        sys.exit(1)

    corriendo = {"v": True}

    def parar(signum, frame):
        corriendo["v"] = False

    signal.signal(signal.SIGINT, parar)
    cliente.loop_start()

    ultimo_reporte = 0.0
    try:
        while corriendo["v"]:
            time.sleep(0.2)
            ahora = time.time()
            if ahora - ultimo_reporte >= 2.0 and canales:
                partes = [
                    f"{c.nombre}: {c.n_muestras} muestras"
                    + (f" ({c.n_perdidos} perdidas)" if c.n_perdidos else "")
                    for c in canales.values()
                ]
                print("  " + " | ".join(partes))
                ultimo_reporte = ahora
    finally:
        cliente.loop_stop()
        cliente.disconnect()
        print("\n=== resumen ===")
        for c in canales.values():
            c.cerrar()
            tasa = 100 * c.n_perdidos / max(1, c.n_mensajes + c.n_perdidos)
            print(f"  {c.nombre:4s}  {c.n_muestras:7d} muestras  "
                  f"{c.n_mensajes:5d} lotes  {c.n_perdidos} perdidos ({tasa:.2f}%)")
        print(f"\nDatos en {directorio}")
        if any(c.n_perdidos for c in canales.values()):
            print("[!] Hubo perdida de lotes: la senal tiene huecos reales. Revisar la red.")


if __name__ == "__main__":
    main()

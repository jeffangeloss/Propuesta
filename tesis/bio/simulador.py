#!/usr/bin/env python3
"""
Simulador de ESP32. Publica señales sintéticas con el mismo formato que el firmware real.

Sirve para validar toda la tubería —broker, suscriptor, escritura, mapeo de relojes,
detección de golpes— sin tocar hardware. Si algo no funciona aquí, tampoco va a funcionar
con sensores, y depurarlo con cables de por medio es mucho más lento.

DERIVA DELIBERADA
-----------------
El reloj simulado corre con un error configurable (--deriva-ppm, 200 ppm por defecto) y
arranca en un offset arbitrario, igual que un ESP32 real: su cristal no es perfecto y su
micros() empieza cuando el chip arranca, no cuando arranca la sesión.

Esto es a propósito. Si `sincronia.py` no detecta y corrige esa deriva conocida, tampoco
va a corregir la real — y ahí sí no hay forma de saber el valor verdadero.

GOLPES DE SINCRONÍA
-------------------
Emite tres picos en el IMU al inicio y tres al final, imitando el protocolo real de dar
tres golpecitos secos al sensor al abrir y cerrar cada bloque.

Uso:
    ./.venv/bin/python simulador.py --duracion 30
    ./.venv/bin/python simulador.py --duracion 30 --perdida 2   # 2% de lotes perdidos
"""

import argparse
import json
import math
import random
import sys
import time

import paho.mqtt.client as mqtt

# (tópico, Hz, muestras por lote, canales)
CANALES = [
    ("imu", 50, 10, ["ax", "ay", "az"]),
    ("ecg", 250, 50, ["v"]),
    ("gsr", 20, 4, ["v"]),
]

GOLPES_EN = [2.0, None]  # el segundo se calcula desde --duracion
VENTANA_GOLPE = 0.06     # duración de cada pico, en segundos
SEP_GOLPES = 0.25        # separación entre los tres golpes


def valor_imu(t, momentos_golpe):
    """Reposo con ruido leve, más picos en los golpes de sincronía."""
    ax = 0.02 * math.sin(2 * math.pi * 0.3 * t) + random.gauss(0, 0.004)
    ay = 0.02 * math.cos(2 * math.pi * 0.2 * t) + random.gauss(0, 0.004)
    az = 1.0 + random.gauss(0, 0.004)  # gravedad
    for tg in momentos_golpe:
        d = t - tg
        if 0 <= d < VENTANA_GOLPE:
            pico = 2.5 * math.sin(math.pi * d / VENTANA_GOLPE)
            az += pico
            ax += 0.4 * pico
    return ax, ay, az


def valor_ecg(t):
    """QRS sintético a ~72 lpm sobre la línea base del ADC de 12 bits."""
    periodo = 60.0 / 72.0
    f = (t % periodo) / periodo
    v = 0.0
    if 0.10 < f < 0.16:                      # onda P
        v += 120 * math.sin(math.pi * (f - 0.10) / 0.06)
    if 0.18 < f < 0.22:                      # complejo QRS
        v += 1400 * math.sin(math.pi * (f - 0.18) / 0.04)
    if 0.20 < f < 0.215:
        v -= 400 * math.sin(math.pi * (f - 0.20) / 0.015)
    if 0.30 < f < 0.42:                      # onda T
        v += 260 * math.sin(math.pi * (f - 0.30) / 0.12)
    return int(2048 + v + random.gauss(0, 12))


def valor_gsr(t):
    """Nivel tónico con deriva lenta más respuestas fásicas ocasionales."""
    tonico = 1500 + 90 * math.sin(2 * math.pi * t / 45.0)
    fasico = 0.0
    for inicio in (7.0, 19.0, 31.0, 44.0):
        d = t - inicio
        if 0 <= d < 6:
            fasico += 170 * math.exp(-d / 2.2) * (1 - math.exp(-d / 0.35))
    return int(tonico + fasico + random.gauss(0, 5))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--duracion", type=float, default=30.0, help="segundos")
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--puerto", type=int, default=1883)
    ap.add_argument("--deriva-ppm", type=float, default=200.0,
                    help="error del cristal simulado, en partes por millon")
    ap.add_argument("--perdida", type=float, default=0.0,
                    help="porcentaje de lotes descartados a proposito")
    args = ap.parse_args()

    GOLPES_EN[1] = max(args.duracion - 2.0, 3.0)
    momentos_golpe = [b + i * SEP_GOLPES for b in GOLPES_EN for i in range(3)]

    cliente = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    try:
        cliente.connect(args.host, args.puerto, keepalive=30)
    except OSError as e:
        print(f"[!] No se pudo conectar al broker: {e}")
        print("    ¿Esta corriendo?  mosquitto -c tesis/bio/mosquitto.conf -v")
        sys.exit(1)
    cliente.loop_start()

    # Reloj del "ESP32": offset arbitrario y deriva conocida.
    offset_us = random.randint(5_000_000, 90_000_000)
    factor = 1.0 + args.deriva_ppm / 1e6

    print(f"Simulando {args.duracion:.0f} s")
    print(f"  deriva del cristal : {args.deriva_ppm:+.0f} ppm  (factor {factor:.6f})")
    print(f"  offset inicial     : {offset_us / 1e6:.1f} s")
    print(f"  golpes de sincronia: {', '.join(f'{t:.2f}' for t in momentos_golpe)} s")
    if args.perdida:
        print(f"  perdida simulada   : {args.perdida:.1f}%")
    print()

    estado = {n: {"seq": 0, "siguiente": 0.0} for n, _, _, _ in CANALES}
    t_inicio = time.perf_counter()
    enviados = descartados = 0

    try:
        while True:
            ahora = time.perf_counter() - t_inicio
            if ahora >= args.duracion:
                break

            for nombre, hz, tam, columnas in CANALES:
                st = estado[nombre]
                dt = 1.0 / hz
                periodo_lote = tam * dt
                if ahora < st["siguiente"] + periodo_lote:
                    continue

                t0 = st["siguiente"]
                st["siguiente"] += periodo_lote

                series = {c: [] for c in columnas}
                for i in range(tam):
                    t = t0 + i * dt
                    if nombre == "imu":
                        ax, ay, az = valor_imu(t, momentos_golpe)
                        series["ax"].append(round(ax, 5))
                        series["ay"].append(round(ay, 5))
                        series["az"].append(round(az, 5))
                    elif nombre == "ecg":
                        series["v"].append(valor_ecg(t))
                    else:
                        series["v"].append(valor_gsr(t))

                st["seq"] += 1
                # El seq avanza aunque el lote se descarte: así el suscriptor detecta el hueco.
                if args.perdida and random.random() * 100 < args.perdida:
                    descartados += 1
                    continue

                payload = {
                    "seq": st["seq"],
                    "t_us": int(offset_us + t0 * 1e6 * factor),
                    "dt_us": int(dt * 1e6 * factor),
                }
                payload.update(series)
                cliente.publish(f"tesis/bio/{nombre}", json.dumps(payload), qos=0)
                enviados += 1

            time.sleep(0.002)
    except KeyboardInterrupt:
        print("\nInterrumpido.")
    finally:
        time.sleep(0.4)  # deja salir lo que quede en cola
        cliente.loop_stop()
        cliente.disconnect()
        print(f"\n{enviados} lotes enviados, {descartados} descartados a proposito.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Mapeo del reloj del ESP32 al reloj del PC, y detección de los golpes de sincronía.

EL PROBLEMA
-----------
El ESP32 marca cada muestra con su micros(): espaciado preciso, pero cero arbitrario y
cristal con deriva. El PC estampa la llegada de cada lote: reloj correcto —el mismo que usa
la telemetría del juego— pero contaminado con el jitter del WiFi.

Hay que combinar los dos: espaciado del ESP32, anclaje absoluto del PC.

POR QUÉ NO SIRVE UN AJUSTE POR MÍNIMOS CUADRADOS DIRECTO
--------------------------------------------------------
La latencia de red es siempre positiva: un lote puede llegar tarde, nunca temprano. Eso
hace que el error no esté centrado en cero y que un ajuste ordinario quede sesgado hacia
las llegadas lentas.

La relación verdadera está en la ENVOLVENTE INFERIOR: los lotes que llegaron con la mínima
latencia posible. Por eso se ajusta iterativamente sobre el cuartil de menor residuo.

Uso:
    ./.venv/bin/python sincronia.py <directorio_de_sesion>
    ./.venv/bin/python sincronia.py <directorio> --juego <telemetria_del_juego.csv>
"""

import argparse
import csv
import os
import sys

import numpy as np

CUANTIL_ENVOLVENTE = 0.25   # fracción de lotes menos demorados usados en el ajuste final
ITERACIONES = 4
UMBRAL_GOLPE_G = 0.8        # aceleración sobre el reposo para contar como golpe
REFRACTARIO_S = 0.10        # separación mínima entre golpes
HUECO_GRUPO_S = 1.5         # separación que corta un grupo de golpes


def leer_csv(ruta):
    filas = [l for l in open(ruta) if not l.startswith("#")]
    return list(csv.DictReader(filas))


def ajustar_reloj(filas):
    """Devuelve (pendiente, intercepto, ppm, jitter_ms, n) de esp_us -> unix_ms."""
    # Un punto por lote: el primero de cada mensaje es el que lleva la marca real de llegada.
    vistos, xs, ys = set(), [], []
    for f in filas:
        seq = f["msg_seq"]
        if seq in vistos:
            continue
        vistos.add(seq)
        xs.append(float(f["esp_us"]))
        ys.append(float(f["llegada_ms"]))
    x, y = np.array(xs), np.array(ys)
    if len(x) < 10:
        raise SystemExit("[!] Muy pocos lotes para ajustar el reloj.")

    idx = np.arange(len(x))
    for _ in range(ITERACIONES):
        a, b = np.polyfit(x[idx], y[idx], 1)
        residuos = y - (a * x + b)           # positivo = llego tarde
        corte = np.quantile(residuos, CUANTIL_ENVOLVENTE)
        idx = np.where(residuos <= corte)[0]
        if len(idx) < 8:
            break

    a, b = np.polyfit(x[idx], y[idx], 1)
    residuos = y - (a * x + b)
    # `a` convierte us -> ms: valdría exactamente 0.001 si ambos relojes fueran idénticos.
    # Se invierte para expresar la velocidad del CRISTAL DEL ESP32 respecto al PC:
    # positivo = el ESP32 corre adelantado. Sin invertir, el signo queda al revés de lo
    # que uno espera al leer "deriva del cristal".
    ppm = (0.001 / a - 1.0) * 1e6
    return a, b, ppm, float(np.std(residuos[idx])), len(x)


def detectar_golpes(filas, a, b):
    """Encuentra los picos del IMU y los agrupa. Devuelve grupos de tiempos en unix_ms."""
    esp = np.array([float(f["esp_us"]) for f in filas])
    mag = np.sqrt(
        np.array([float(f["ax"]) for f in filas]) ** 2
        + np.array([float(f["ay"]) for f in filas]) ** 2
        + np.array([float(f["az"]) for f in filas]) ** 2
    )
    base = np.median(mag)
    exceso = np.abs(mag - base)

    fs = 1e6 / np.median(np.diff(esp))
    refractario = max(1, int(REFRACTARIO_S * fs))

    picos, i = [], 1
    while i < len(exceso) - 1:
        if exceso[i] > UMBRAL_GOLPE_G and exceso[i] >= exceso[i - 1] and exceso[i] > exceso[i + 1]:
            picos.append(i)
            i += refractario
        else:
            i += 1

    grupos, actual = [], []
    for p in picos:
        t = a * esp[p] + b
        if actual and (t - actual[-1]) / 1000.0 > HUECO_GRUPO_S:
            grupos.append(actual)
            actual = []
        actual.append(t)
    if actual:
        grupos.append(actual)
    return grupos, fs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("directorio")
    ap.add_argument("--juego", help="CSV de telemetria del juego, para contrastar")
    args = ap.parse_args()

    ruta_imu = os.path.join(args.directorio, "imu.csv")
    if not os.path.exists(ruta_imu):
        sys.exit(f"[!] No existe {ruta_imu}")

    filas = leer_csv(ruta_imu)
    a, b, ppm, jitter, n = ajustar_reloj(filas)

    print("=== mapeo de relojes (esp_us -> unix_ms) ===")
    print(f"  lotes usados       : {n}")
    print(f"  deriva del cristal : {ppm:+.1f} ppm")
    print(f"  jitter residual    : {jitter:.2f} ms (sd sobre la envolvente)")
    dur_s = (float(filas[-1]['esp_us']) - float(filas[0]['esp_us'])) / 1e6
    print(f"  duracion           : {dur_s:.1f} s")
    print(f"  error acumulado si se ignorara la deriva: {abs(ppm) * dur_s / 1000:.1f} ms")

    grupos, fs = detectar_golpes(filas, a, b)
    print(f"\n=== golpes de sincronia (IMU a {fs:.0f} Hz) ===")
    if not grupos:
        print("  ninguno detectado. ¿Se dieron los golpes? ¿El umbral es adecuado?")
    for i, g in enumerate(grupos, 1):
        t0 = g[0]
        sep = [f"{(t - t0) / 1000:.3f}" for t in g[1:]]
        print(f"  grupo {i}: {len(g)} golpes  t={t0:.1f} unix_ms" +
              (f"  separaciones={sep} s" if sep else ""))
        if len(g) != 3:
            print(f"           [!] se esperaban 3, hay {len(g)}. Revisar umbral o ejecucion.")

    if args.juego:
        marcas = [
            (f["evento"], float(f["unix_ms"]))
            for f in leer_csv(args.juego)
            if f["evento"] in ("block_start", "block_end")
        ]
        print("\n=== contraste con la telemetria del juego ===")
        for nombre, t in marcas:
            cercano = min((g[0] for g in grupos), key=lambda x: abs(x - t), default=None)
            if cercano is None:
                print(f"  {nombre}: sin grupo de golpes con que comparar")
            else:
                print(f"  {nombre}: {t:.1f} vs golpes {cercano:.1f}  ->  {cercano - t:+.0f} ms")
        print("\n  Este desfase es el que hay que reportar en el metodo.")


if __name__ == "__main__":
    main()

#!/bin/bash
# Prueba de humo de la tubería biométrica, sin hardware.
#
# Levanta el broker, arranca el suscriptor, corre el simulador y verifica el resultado.
# Si esto falla, no tiene sentido conectar sensores todavía.
#
#   ./prueba_tuberia.sh [segundos] [porcentaje_de_perdida]

set -u
cd "$(dirname "$0")"

DURACION="${1:-12}"
PERDIDA="${2:-0}"
PY="./.venv/bin/python"
BROKER="$(brew --prefix 2>/dev/null)/sbin/mosquitto"
[ -x "$BROKER" ] || BROKER="mosquitto"

limpiar() {
  [ -n "${PID_SUB:-}" ] && kill -INT "$PID_SUB" 2>/dev/null
  [ -n "${PID_BROKER:-}" ] && kill "$PID_BROKER" 2>/dev/null
  wait 2>/dev/null
}
trap limpiar EXIT

echo "=== 1/4  broker ==="
"$BROKER" -c mosquitto.conf &
PID_BROKER=$!
sleep 1
kill -0 "$PID_BROKER" 2>/dev/null || { echo "[!] el broker no arranco"; exit 1; }
echo "    mosquitto en pid $PID_BROKER"

echo "=== 2/4  suscriptor ==="
$PY suscriptor.py --participante prueba --condicion tuberia > /tmp/suscriptor_prueba.log 2>&1 &
PID_SUB=$!
sleep 2

echo "=== 3/4  simulador (${DURACION}s, perdida ${PERDIDA}%) ==="
$PY simulador.py --duracion "$DURACION" --perdida "$PERDIDA"

sleep 1
kill -INT "$PID_SUB" 2>/dev/null
wait "$PID_SUB" 2>/dev/null
PID_SUB=""

echo
echo "=== 4/4  resultado ==="
cat /tmp/suscriptor_prueba.log | tail -12

/*
 * Nodo de captura biométrica — ESP32-D0WD-V3 (WROOM-32)
 *
 * Hito 2b: solo el MPU-6050. Es I2C, digital y no toca el ADC, así que permite validar
 * publicación, formato y golpes de sincronía sin pelear con ruido analógico.
 * ECG (AD8232) y GSR entran después; el pinout está reservado en el README.
 *
 * Publica en tesis/bio/imu lotes JSON con el mismo formato que simulador.py:
 *   {"seq":42,"t_us":1234567,"dt_us":20000,"ax":[...],"ay":[...],"az":[...]}
 *
 * Este archivo queda casi vacío a propósito: toda la lógica está en nodo.cpp.
 * La razón está explicada en nodo.h — resumen: el preprocesador de sketches necesita un
 * `ctags` que solo existe compilado para Intel, y en Apple Silicon sin Rosetta no corre.
 *
 * Antes de compilar:  cp credenciales.ejemplo.h credenciales.h  y editarlo.
 *
 * Compilar y cargar:
 *   arduino-cli compile --fqbn esp32:esp32:esp32 tesis/bio/firmware
 *   arduino-cli upload  --fqbn esp32:esp32:esp32 -p /dev/cu.usbserial-110 tesis/bio/firmware
 *
 * Monitor serie:
 *   arduino-cli monitor -p /dev/cu.usbserial-110 --config baudrate=115200
 */

#include "nodo.h"

void setup() {
  nodoSetup();
}

void loop() {
  nodoLoop();
}

#!/bin/sh
# Pruebas de la lógica pura del intercambio con el intérprete de Haxe.
# Copia IntercambioLogica.hx a una carpeta temporal porque source/import.hx
# importaría flixel en cualquier archivo compilado desde source/.
set -e
cd "$(dirname "$0")/../.."
TMP=$(mktemp -d)
mkdir -p "$TMP/backend"
cp source/backend/IntercambioLogica.hx "$TMP/backend/"
haxe -cp "$TMP" -cp tesis/pruebas -main TestIntercambio --interp
# Teclas de nota del modo experimento. FlxKey es un Int en tiempo de compilación,
# así que basta con -lib flixel; no hace falta abrir el juego.
cp source/backend/TeclasExperimento.hx "$TMP/backend/"
haxe -lib flixel -cp "$TMP" -cp tesis/pruebas -main TestTeclasExperimento --interp
rm -rf "$TMP"

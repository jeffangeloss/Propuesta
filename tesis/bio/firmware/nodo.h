/*
 * Nodo de captura biométrica — interfaz.
 *
 * Todo el código vive en nodo.cpp y no en el .ino a propósito.
 *
 * El preprocesador de sketches de arduino-cli usa `ctags` para insertar prototipos de
 * función automáticamente, y ese binario viene compilado solo para Intel. En un Mac con
 * Apple Silicon sin Rosetta no corre, y universal-ctags no sirve de reemplazo: genera otro
 * formato y los prototipos terminan insertados DENTRO de los cuerpos de las funciones.
 *
 * Los archivos .cpp de la carpeta del sketch se compilan tal cual, sin preprocesar. Dejando
 * el .ino con solo setup() y loop() —que ya están declarados en Arduino.h y por tanto no
 * necesitan prototipo— el problema desaparece por completo.
 */

#pragma once

void nodoSetup();
void nodoLoop();

/*
 * Nodo de captura biométrica — ESP32-D0WD-V3 (WROOM-32)
 *
 * ┌───────────────────────────────────────────────────────────────────────────────────┐
 * │  ESTE ARCHIVO DEBE QUEDARSE VACÍO. NO AGREGAR FUNCIONES AQUÍ.                      │
 * │                                                                                    │
 * │  arduino-cli preprocesa los .ino con `ctags` para insertar prototipos, y ese       │
 * │  binario solo existe compilado para Intel. En Apple Silicon sin Rosetta hay que    │
 * │  sustituirlo por universal-ctags, que genera posiciones distintas: los prototipos  │
 * │  terminan insertados DENTRO de los cuerpos de función y, al perder el tipo de      │
 * │  retorno, se convierten en LLAMADAS.                                               │
 * │                                                                                    │
 * │  Con setup() aquí, el preprocesador producía literalmente esto:                    │
 * │                                                                                    │
 * │      void setup() {                                                                │
 * │        setup();      // <- recursion infinita                                      │
 * │        loop();                                                                     │
 * │        ...                                                                         │
 * │      }                                                                             │
 * │                                                                                    │
 * │  Compilaba sin un solo error y la placa entraba en Guru Meditation (Double         │
 * │  exception) por desbordamiento de pila, antes de imprimir nada.                    │
 * │                                                                                    │
 * │  Sin funciones en el .ino, ctags no encuentra nada que insertar y el problema      │
 * │  desaparece. Los .cpp de la carpeta se compilan tal cual, sin preprocesar, así     │
 * │  que TODO el código —incluidos setup() y loop()— vive en nodo.cpp.                 │
 * └───────────────────────────────────────────────────────────────────────────────────┘
 *
 * Antes de compilar:  cp credenciales.ejemplo.h credenciales.h  y editarlo.
 *
 *   arduino-cli compile --fqbn esp32:esp32:esp32 tesis/bio/firmware
 *   arduino-cli upload  --fqbn esp32:esp32:esp32:UploadSpeed=115200 \
 *                       -p /dev/cu.usbserial-110 tesis/bio/firmware
 *
 * Verificar que el preprocesador no ensució nada (debe salir vacío):
 *   grep -nE '^\s+(setup|loop)\(\);' <build>/sketch/firmware.ino.cpp
 */

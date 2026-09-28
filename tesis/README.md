# Instrumento experimental — tesis

Fork de Friday Night Funkin' Psych Engine 1.0.4 adaptado como **instrumento de medición** para
un experimento sobre estado de flow, desempeño rítmico y ajuste dinámico de dificultad.

- **Autor:** Jefferson Angelo Sanchez Palacios (20235218)
- **Asesor:** Hernán Alejandro Quintana Cruz
- **Universidad de Lima** — Carrera de Ingeniería de Sistemas

## Pregunta de investigación

> ¿El ajuste dinámico de dificultad basado en señales biométricas multimodales iguala el estado
> de flow entre jugadores con y sin formación musical, o beneficia principalmente a quienes ya
> poseen mayor habilidad rítmica?

Diseño factorial mixto 2 × 2: formación musical (entre-sujetos) × condición adaptativa/estática
(intra-sujeto, contrabalanceada).

## Documentos

| Archivo | Contenido |
|---|---|
| **[ESTADO.md](ESTADO.md)** | **Empezar por aquí.** Hito actual, qué sigue y qué está bloqueado |
| [ESPECIFICACION-TELEMETRIA.md](ESPECIFICACION-TELEMETRIA.md) | Formato del CSV, eventos, convenciones y cálculo de variables |
| [PROTOCOLO-MODO-EXPERIMENTO.md](PROTOCOLO-MODO-EXPERIMENTO.md) | Qué cambia en modo experimento y por qué |

---

## Entorno de compilación

> ⚠️ **El script `setup/unix.sh` del engine NO funciona en Mac con Apple Silicon.**
> Instala **lime 8.1.2**, cuyo `lime.ndll` viene compilado solo para x86_64. Con un Haxe/neko
> arm64 el build falla con `incompatible architecture (have 'x86_64', need 'arm64')`.
> Hay que usar **lime 8.2.2 o superior** — la 8.2.0 añadió soporte de Apple Silicon e incluye
> la carpeta `ndll/MacArm64/`. `lime rebuild` no sirve como alternativa: el paquete de haxelib
> no trae las fuentes nativas y el comando termina sin hacer nada.

Verificado en MacBook Air M4, macOS con Command Line Tools de Xcode instaladas.

```bash
brew install haxe                        # 4.3.7
echo 'export HAXE_STD_PATH="/opt/homebrew/lib/haxe/std"' >> ~/.zshrc

mkdir -p ~/haxelib && haxelib setup ~/haxelib
haxelib install lime 8.2.2               # NO 8.1.2
haxelib install openfl 9.3.3
haxelib install flixel 5.6.1
haxelib install flixel-addons 3.2.2
haxelib install flixel-tools 1.5.1
haxelib install tjson 1.4.0
haxelib install hscript-iris 1.1.3
haxelib install format
haxelib install hxp
haxelib install hxcpp
haxelib git flxanimate https://github.com/Dot-Stuff/flxanimate 768740a56b26aa0c072720e0d1236b94afe68e3e

# solo para el build de desarrollo, que incluye las canciones del juego base
haxelib git funkin.vis https://github.com/FunkinCrew/funkVis 22b1ce089dd924f15cdc4632397ef3504d464e90
haxelib git grig.audio https://gitlab.com/haxe-grig/grig.audio.git cbf91e2180fd2e374924fe74844086aab7891666
```

En `Project.xml` están comentados `LUA_ALLOWED` y `DISCORD_ALLOWED`: son librerías nativas
innecesarias para el estudio y son las que más problemas dan al compilar en ARM.

## Compilar

```bash
haxelib run lime build mac -DBASE_GAME_FILES   # desarrollo: incluye canciones del juego base
haxelib run lime build mac                     # sesiones: solo los charts propios
```

En macOS 27 hay que agregar `-DMACOSX_VER=27.0` a los dos comandos. hxcpp 4.3.2 elige la versión
del SDK leyendo la carpeta de SDKs y toma `MacOSX27.sdk`, que `xcrun` no reconoce como
`macosx27`. Sin ese flag la compilación termina con `Could not create PCH`.

Pruebas de la lógica del intercambio, sin abrir el juego:

```bash
./tesis/pruebas/correr_pruebas.sh
```

El flag va por línea de comandos y no en `Project.xml` a propósito. **El build de las sesiones
no debe incluir las canciones del juego base**: si el participante entra a Freeplay y ve siete
semanas de canciones puede elegir otra cosa o llegar con familiaridad previa a un tema, lo que
contamina el protocolo.

Salida en `export/release/macos/bin/PsychEngine.app` (ignorado por git).

## Ejecutar una sesión

1. Editar `~/Documents/fnf-telemetria/sesion.txt` (el juego lo crea solo la primera vez):

   ```
   participante=P01
   condicion=adaptativa
   experimento=1
   ```

   Se **relee al iniciar cada canción**, así que se puede cambiar de condición entre bloques sin
   cerrar el juego.

2. Verificar la calibración de audio del juego **en la máquina y con la salida de audio exactas
   de las sesiones**. Audífonos o parlantes **con cable**: el Bluetooth añade entre 100 y 300 ms
   de latencia variable y arruina la medición sin dar ninguna señal de que algo va mal.

3. Jugar el bloque completo. Los CSV quedan en `~/Documents/fnf-telemetria/`.

## Modificaciones al código del engine

Todas marcadas con el comentario `// FNF-MOTIV [función]`, donde la función es `registro`, `intercambio` o `modo experimento`, para poder localizarlas con `grep -rn "FNF-MOTIV" source/` o, por función, con `grep -rn "FNF-MOTIV \[registro\]" source/`.

| Archivo | Cambio |
|---|---|
| `source/backend/Telemetry.hx` | **Nuevo.** Módulo de registro completo |
| `source/import.hx` | Añade `import backend.Telemetry` |
| `source/states/PlayState.hx` | Error de timing con signo, 8 puntos de registro, bloqueo de pausa, ghost tapping y piso de vida |
| `Project.xml` | `LUA_ALLOWED` y `DISCORD_ALLOWED` comentados |

### Notas para quien modifique el engine

- **`Math.abs()` en `popUpScore()`** descarta el signo del error de timing. El valor firmado se
  captura antes de esa línea.
- **El ghost tapping está bloqueado en dos lugares**, no en uno: `keyPressed()` decide si
  `noteMissPress()` se llama siquiera, y esa función tiene su propia verificación. Hay que
  parchear ambas.
- **Al desactivar defines desaparecen variables que parecen de uso general.** `storyDifficultyText`
  vive dentro de `#if DISCORD_ALLOWED`. Preferir siempre la fuente original del dato
  (`Difficulty.getString()`) antes que una variable de conveniencia declarada en un bloque condicional.

package backend;

import flixel.input.keyboard.FlxKey;

/**
 * FNF-MOTIV [modo experimento]: teclas que juegan las notas en modo experimento.
 *
 * En modo experimento se juega solo con las cuatro flechas y con la mano derecha. La mano izquierda
 * descansa sobre la mesa con los sensores, así que una letra pulsada por ella o por un roce no puede
 * disparar una nota. Los carriles salen de esta tabla fija y no de ClientPrefs.keyBinds: da igual qué
 * controles haya guardado esa máquina en controls_v3.sol, y las preferencias guardadas quedan intactas.
 *
 * Solo usa FlxKey, que es un Int en tiempo de compilación, así que se prueba con el intérprete de Haxe
 * (tesis/pruebas/correr_pruebas.sh) sin abrir el juego.
 */
class TeclasExperimento
{
	/** Una tecla por carril, en el orden de PlayState.keysArray: izquierda, abajo, arriba, derecha. */
	public static final NOTAS:Array<FlxKey> = [FlxKey.LEFT, FlxKey.DOWN, FlxKey.UP, FlxKey.RIGHT];

	/** Carril que juega la tecla, o -1 si no es una de las cuatro flechas. */
	public static function carril(tecla:FlxKey):Int
		return NOTAS.indexOf(tecla);
}

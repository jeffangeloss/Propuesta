import backend.TeclasExperimento.carril;
import flixel.input.keyboard.FlxKey;

/** Pruebas de las teclas de nota del modo experimento. Se corren con tesis/pruebas/correr_pruebas.sh */
class TestTeclasExperimento
{
	static var fallas:Int = 0;
	static var total:Int = 0;

	static function ok(cond:Bool, nombre:String):Void
	{
		total++;
		if (!cond) { fallas++; Sys.println('FALLA  ' + nombre); }
	}

	static function main():Void
	{
		// cada flecha toca su carril, en el orden de PlayState.keysArray: izquierda, abajo, arriba, derecha
		ok(carril(FlxKey.LEFT) == 0, 'flecha izquierda -> carril 0');
		ok(carril(FlxKey.DOWN) == 1, 'flecha abajo -> carril 1');
		ok(carril(FlxKey.UP) == 2, 'flecha arriba -> carril 2');
		ok(carril(FlxKey.RIGHT) == 3, 'flecha derecha -> carril 3');

		// las teclas alternas que trae el motor por defecto, y otras al alcance de la mano izquierda
		for (nombre in ['A', 'S', 'W', 'D', 'R', 'Q', 'E', 'Z', 'X', 'TAB', 'CAPSLOCK', 'SHIFT', 'CONTROL', 'SPACE', 'ESCAPE', 'ENTER'])
			ok(carril(FlxKey.fromString(nombre)) == -1, nombre + ' no dispara notas');

		// ninguna otra tecla de la tabla de flixel dispara una nota
		var carriles:Map<String, Int> = ['LEFT' => 0, 'DOWN' => 1, 'UP' => 2, 'RIGHT' => 3];
		for (nombre => tecla in FlxKey.fromStringMap)
		{
			var esperado:Int = carriles.exists(nombre) ? carriles.get(nombre) : -1;
			ok(carril(tecla) == esperado, nombre + ' -> carril ' + esperado + ' (obtuvo ' + carril(tecla) + ')');
		}

		ok(carril(FlxKey.NONE) == -1, 'NONE no dispara notas');

		Sys.println((total - fallas) + ' de ' + total + ' pruebas pasan');
		Sys.exit(fallas == 0 ? 0 : 1);
	}
}

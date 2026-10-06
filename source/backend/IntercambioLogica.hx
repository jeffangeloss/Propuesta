package backend;

/**
 * FNF-MOTIV [intercambio]: lógica pura del intercambio de versiones del chart.
 *
 * No importa nada de flixel ni de lime, así que se prueba con el intérprete de Haxe
 * (tesis/pruebas/correr_pruebas.sh) sin abrir el juego.
 *
 * Un corte cae al inicio de cada grupo de 8 secciones. El segmento k reúne las notas cuya
 * cabeza cae en [cortes[k], cortes[k+1]). El segmento k+1 se entrega a la fila de aparición
 * en su plazo, antes de que cualquiera de sus notas llegue a la pantalla.
 */
typedef SeccionMinima =
{
	var sectionBeats:Null<Float>;
	@:optional var changeBPM:Null<Bool>;
	@:optional var bpm:Null<Float>;
}

typedef DecisionValida =
{
	var decision:String;
	var seq:Int;
	var fuente:String;
	var unixMs:Float;
}

class IntercambioLogica
{
	public static inline var COMPASES_POR_CORTE:Int = 8;
	public static inline var APARICION_MS:Float = 2000;
	public static inline var MARGEN_MS:Float = 250;

	public static inline var FACIL:Int = 0;
	public static inline var MEDIA:Int = 1;
	public static inline var DIFICIL:Int = 2;
	public static final NOMBRES:Array<String> = ['facil', 'media', 'dificil'];

	/**
	 * Inicio en ms de cada sección, más el final de la última (length = secciones + 1).
	 * Replica la cuenta de Conductor.mapBPMChanges para que los cortes coincidan con los del motor.
	 */
	public static function iniciosDeSeccion(bpmInicial:Float, secciones:Array<SeccionMinima>):Array<Float>
	{
		var inicios:Array<Float> = [0];
		var bpm:Float = bpmInicial;
		var pos:Float = 0;
		for (s in secciones)
		{
			if (s.changeBPM == true && s.bpm != null && s.bpm != bpm) bpm = s.bpm;
			var beats:Float = (s.sectionBeats == null || Math.isNaN(s.sectionBeats)) ? 4 : s.sectionBeats;
			var pasos:Int = Math.round(beats * 4);
			pos += ((60 / bpm) * 1000 / 4) * pasos;
			inicios.push(pos);
		}
		return inicios;
	}

	/** Tiempos de corte: inicio de las secciones 0, 8, 16... El primero siempre es 0. */
	public static function cortes(inicios:Array<Float>, compasesPorCorte:Int = COMPASES_POR_CORTE):Array<Float>
	{
		var r:Array<Float> = [];
		var secciones:Int = inicios.length - 1;
		var i:Int = 0;
		while (i < Std.int(Math.max(secciones, 1)))
		{
			r.push(inicios[i]);
			i += compasesPorCorte;
		}
		return r;
	}

	/** Segmento de una nota según el tiempo de su cabeza. Lo anterior al primer corte cuenta como segmento 0. */
	public static function segmentoDe(tiempo:Float, cortes:Array<Float>):Int
	{
		var k:Int = 0;
		for (i in 0...cortes.length)
			if (cortes[i] <= tiempo) k = i;
		return k;
	}

	/** Cuánto antes de su momento el motor pasa una nota a la pantalla (PlayState.update). */
	public static function anticipacion(playbackRate:Float, songSpeed:Float, aparicionMs:Float = APARICION_MS):Float
	{
		var t:Float = aparicionMs * playbackRate;
		if (songSpeed < 1) t /= songSpeed;
		return t;
	}

	/** Momento de la canción en que hay que entregar el segmento que empieza en `corte`. */
	public static function plazo(corte:Float, noteOffset:Float, anticipacionMs:Float, margenMs:Float = MARGEN_MS):Float
		return corte + noteOffset - anticipacionMs - margenMs;

	/** Aplica una decisión y acota el resultado entre Fácil y Difícil. */
	public static function aplicar(version:Int, decision:String):Int
	{
		return switch (decision)
		{
			case 'sube': Std.int(Math.min(DIFICIL, version + 1));
			case 'baja': Std.int(Math.max(FACIL, version - 1));
			default: version;
		}
	}

	/**
	 * Valida el contenido de decision.json. Devuelve null si no corresponde al bloque y al
	 * segmento esperados o si le falta algún campo, y entonces la versión se mantiene.
	 */
	public static function validarDecision(json:Dynamic, bloque:String, segmento:Int):Null<DecisionValida>
	{
		if (json == null) return null;
		var b:Dynamic = Reflect.field(json, 'bloque');
		var s:Dynamic = Reflect.field(json, 'segmento');
		var d:Dynamic = Reflect.field(json, 'decision');
		if (b == null || s == null || d == null) return null;
		if (Std.string(b) != bloque) return null;
		if (!Std.isOfType(s, Int) && !Std.isOfType(s, Float)) return null;
		if (Std.int(s) != segmento) return null;
		var dec:String = Std.string(d);
		if (dec != 'sube' && dec != 'baja' && dec != 'queda') return null;
		var q:Dynamic = Reflect.field(json, 'seq');
		var f:Dynamic = Reflect.field(json, 'fuente');
		var u:Dynamic = Reflect.field(json, 'unix_ms');
		return {
			decision: dec,
			seq: (q == null) ? -1 : Std.int(q),
			fuente: (f == null) ? '' : Std.string(f),
			unixMs: (u == null) ? -1 : (u : Float)
		};
	}

	/** Condiciones que acepta el modo experimento en sesion.txt, escritas exactamente así. */
	public static final CONDICIONES:Array<String> = ['adaptativa', 'estatica'];

	/**
	 * Devuelve null si la condición es 'adaptativa' o 'estatica' y, si no, el motivo del rechazo.
	 * No normaliza mayúsculas ni tildes, porque una errata como «Estatica» aplicaría las decisiones.
	 */
	public static function errorCondicion(condicion:Null<String>):Null<String>
	{
		if (condicion != null && CONDICIONES.contains(condicion)) return null;
		return 'la condición «' + condicion + '» de sesion.txt no es válida; debe ser ' + CONDICIONES.join(' o ');
	}

	/** Campo `detalle` del CSV: pares clave=valor separados por punto y coma. */
	public static function detalle(pares:Array<Array<String>>):String
		return [for (p in pares) p[0] + '=' + StringTools.replace(StringTools.replace(p[1], ';', ' '), ',', ' ')].join(';');
}

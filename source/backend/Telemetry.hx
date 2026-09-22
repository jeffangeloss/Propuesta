package backend;

import objects.Note;

#if sys
import sys.io.File;
import sys.io.FileOutput;
import sys.FileSystem;
#end

/**
 * Telemetría de desempeño rítmico para el experimento de tesis.
 *
 * Escribe un CSV por bloque de juego, una fila por evento de nota, en
 * ~/Documents/fnf-telemetria/ (fuera del build, para que no se borre al recompilar).
 *
 * CONVENCIÓN DE SIGNO de timing_error_ms:
 *   negativo = el jugador respondió ADELANTADO respecto a la nota
 *   positivo = el jugador respondió ATRASADO
 * Es la convención estándar en la literatura de sincronización sensoriomotora,
 * donde la asincronía negativa media (NMA) es un hallazgo clásico.
 *
 * Nota sobre `health` en filas de acierto: se registra el valor en el instante
 * del juicio, antes de que se aplique la ganancia de vida de esa misma nota.
 */
class Telemetry
{
	/** Se leen de sesion.txt al iniciar cada bloque. */
	public static var participantId:String = 'test';
	public static var condition:String = 'estatica';
	public static var enabled:Bool = true;

	/**
	 * Modo experimento. Cuando está activo:
	 *   - se bloquea la pausa durante la partida
	 *   - se registran las teclas pulsadas sin nota (ignora ghostTapping)
	 * Se activa poniendo `experimento=1` en sesion.txt. NO cambia las preferencias guardadas.
	 */
	public static var experimentMode:Bool = false;

	/** TESIS: `prueba_auto=1` registra la telemetría también en modo automático (botplay), solo para pruebas. */
	public static var pruebaAuto:Bool = false;

	/** TESIS: `intercambio=1` activa el intercambio de versiones aunque no haya modo experimento. */
	public static var intercambioForzado:Bool = false;

	/** TESIS: líneas de cabecera que agrega el intercambio de versiones antes de abrir el bloque. */
	public static var cabeceraExtra:Array<String> = [];

	/** TESIS: un cuadro más largo que esto se registra como `cuadro_largo` (el doble de 60 cuadros por segundo). */
	public static inline var CUADRO_LARGO_MS:Float = 33;

	/**
	 * Piso de vida en modo experimento. Positivo pero mínimo: la barra se ve vacía,
	 * así que la amenaza percibida se conserva, y una falla más vuelve a cruzar el umbral.
	 */
	public static inline var HEALTH_FLOOR:Float = 0.025;

	/**
	 * Umbral de recuperación (histéresis). Sin esto, como el daño por fallo (0.05) supera al
	 * piso, cada tecla pulsada estando en el suelo contaría como un cruce nuevo. Hay que
	 * recuperarse por encima de este valor para que el siguiente cruce sea un episodio distinto.
	 */
	public static inline var RECOVERY_THRESHOLD:Float = 0.15;

	/** true mientras el jugador está en estado de fracaso (vida en el piso). */
	public static var inFailure(default, null):Bool = false;

	public static var currentFile(default, null):String = '';

	static var seq:Int = 0;

	/** Evita emitir un `resume` sin su `pause` (pasa al cerrar el game over). */
	static var pauseLogged:Bool = false;
	#if sys
	static var out:FileOutput = null;
	#end

	public static function baseDir():String
	{
		#if sys
		var home:String = Sys.getEnv('HOME');
		if (home == null || home.length == 0) home = Sys.getEnv('USERPROFILE');
		if (home == null || home.length == 0) return 'telemetria';
		return home + '/Documents/fnf-telemetria';
		#else
		return 'telemetria';
		#end
	}

	/**
	 * Lee sesion.txt (participante, condicion, experimento) desde el directorio de telemetría.
	 * Se relee en cada bloque, así puedes cambiar de condición entre bloques sin cerrar el juego.
	 * Si el archivo no existe, lo crea con valores por defecto.
	 */
	public static function loadSessionConfig():Void
	{
		#if sys
		var path:String = baseDir() + '/sesion.txt';
		try
		{
			if (!FileSystem.exists(path))
			{
				File.saveContent(path,
					'# Configuracion de sesion. Se relee al iniciar cada cancion.\n'
					+ '# experimento=1 bloquea la pausa y registra teclas pulsadas sin nota.\n'
					+ 'participante=test\n'
					+ 'condicion=estatica\n'
					+ 'experimento=0\n');
				return;
			}

			pruebaAuto = false;
			intercambioForzado = false;
			for (line in StringTools.replace(File.getContent(path), '\r', '').split('\n'))
			{
				var t:String = StringTools.trim(line);
				if (t.length == 0 || t.charAt(0) == '#') continue;
				var i:Int = t.indexOf('=');
				if (i < 0) continue;
				var key:String = StringTools.trim(t.substr(0, i)).toLowerCase();
				var val:String = StringTools.trim(t.substr(i + 1));
				switch (key)
				{
					case 'participante': participantId = val;
					case 'condicion': condition = val;
					case 'experimento': experimentMode = (val == '1' || val.toLowerCase() == 'true');
					case 'prueba_auto': pruebaAuto = (val == '1' || val.toLowerCase() == 'true');
					case 'intercambio': intercambioForzado = (val == '1' || val.toLowerCase() == 'true');
				}
			}
		}
		catch (e:Dynamic)
		{
			trace('[Telemetria] no se pudo leer sesion.txt -> $e');
		}
		#end
	}

	public static function startBlock(song:String, difficulty:String, playbackRate:Float):Void
	{
		#if sys
		if (!enabled) return;
		closeBlock();

		var dir:String = baseDir();
		try
		{
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
		}
		catch (e:Dynamic)
		{
			trace('[Telemetria] no se pudo crear el directorio $dir -> $e');
			return;
		}

		loadSessionConfig();
		seq = 0;
		pauseLogged = false;
		inFailure = false;
		currentFile = dir + '/' + safe(participantId) + '_' + safe(condition) + '_' + safe(song) + '_' + stamp() + '.csv';

		try
		{
			out = File.write(currentFile, false);
		}
		catch (e:Dynamic)
		{
			trace('[Telemetria] no se pudo abrir $currentFile -> $e');
			out = null;
			return;
		}

		// Metadatos como comentarios: pandas los salta con read_csv(..., comment='#')
		raw('# participante=' + participantId);
		raw('# condicion=' + condition);
		raw('# cancion=' + song);
		raw('# dificultad=' + difficulty);
		raw('# playback_rate=' + playbackRate);
		raw('# rating_offset_ms=' + ClientPrefs.data.ratingOffset);
		raw('# note_offset_ms=' + ClientPrefs.data.noteOffset);
		raw('# ventana_sick_ms=' + ClientPrefs.data.sickWindow);
		raw('# ventana_good_ms=' + ClientPrefs.data.goodWindow);
		raw('# ventana_bad_ms=' + ClientPrefs.data.badWindow);
		raw('# modo_experimento=' + (experimentMode ? '1' : '0'));
		raw('# piso_de_vida=' + (experimentMode ? Std.string(HEALTH_FLOOR) : 'sin piso, la muerte termina el bloque'));
		raw('# umbral_recuperacion=' + RECOVERY_THRESHOLD);
		raw('# failure_threshold marca la ENTRADA al fracaso y failure_recovered la salida.');
		raw('# Contar pares para episodios; restar sus song_time_ms para el tiempo en fracaso.');
		raw('# ghost_tapping_efectivo=' + ((ClientPrefs.data.ghostTapping && !experimentMode) ? '1' : '0'));
		raw('# timing_error_ms: negativo=adelantado, positivo=atrasado');
		raw('# ATENCION: si aparecen filas pause/resume, el reloj de pared y el tiempo de cancion');
		raw('# dejan de corresponder a partir de ahi. Usar esas filas para reconstruir el desfase.');
		raw('# version, segmento y nota_ms son de la NOTA (no de la version que suena al registrar la fila)');
		for (linea in cabeceraExtra) raw(linea);
		raw('seq,unix_ms,song_time_ms,evento,direccion,juicio,timing_error_ms,combo,score,health,sustain,version,segmento,nota_ms,detalle');

		row('block_start', -1, '', null, 0, 0, 1.0, false, 0);
		#end
	}

	public static function logHit(songTimeMs:Float, direction:Int, judgment:String, timingErrorMs:Float, combo:Int, score:Int, health:Float,
			isSustain:Bool, ?note:Note):Void
	{
		#if sys
		row('hit', direction, judgment, timingErrorMs, combo, score, health, isSustain, songTimeMs, versionDe(note), segmentoDe(note), notaMs(note));
		#end
	}

	/** TESIS: `sustain` = 1 marca el fallo de la cabeza de una nota larga (antes no se registraba). */
	public static function logMiss(songTimeMs:Float, direction:Int, combo:Int, score:Int, health:Float, pressedWithoutNote:Bool, ?note:Note,
			sustain:Bool = false):Void
	{
		#if sys
		row(pressedWithoutNote ? 'miss_press' : 'miss', direction, '', null, combo, score, health, sustain, songTimeMs, versionDe(note), segmentoDe(note),
			notaMs(note));
		#end
	}

	/** TESIS: decisión aplicada al segmento que entra. `version` y `segmento` son los del segmento. */
	public static function logDecision(songTimeMs:Float, version:String, segmento:Int, detalle:String, combo:Int, score:Int, health:Float):Void
	{
		#if sys
		row('decision', -1, '', null, combo, score, health, false, songTimeMs, version, segmento, null, detalle);
		#end
	}

	/** TESIS: la canción cruzó un corte; `version` es la que empieza a sonar. */
	public static function logCorte(songTimeMs:Float, version:String, segmento:Int, combo:Int, score:Int, health:Float):Void
	{
		#if sys
		row('chart_cut', -1, '', null, combo, score, health, false, songTimeMs, version, segmento);
		#end
	}

	/** TESIS: cuadro más largo que CUADRO_LARGO_MS, para la prueba de imperceptibilidad. */
	public static function logCuadroLargo(songTimeMs:Float, duracionMs:Float):Void
	{
		#if sys
		row('cuadro_largo', -1, '', null, 0, 0, 0, false, songTimeMs, '', -1, null, 'duracion_ms=' + fmt(duracionMs));
		#end
	}

	/** Nombre del bloque en curso: el nombre del CSV sin carpeta ni extensión. */
	public static function bloqueActual():String
	{
		#if sys
		if (out == null) return ''; // TESIS: sin bloque abierto no hay decisiones que validar
		#end
		return currentFile == '' ? '' : haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(currentFile));
	}

	/** El reloj de pared sigue corriendo mientras el tiempo de canción se congela. */
	public static function logPause(songTimeMs:Float, combo:Int, score:Int, health:Float):Void
	{
		#if sys
		if (out == null) return;
		pauseLogged = true;
		row('pause', -1, '', null, combo, score, health, false, songTimeMs);
		#end
	}

	/** Solo se emite si hubo un `pause` previo: cerrar el game over también dispara closeSubState(). */
	public static function logResume(songTimeMs:Float, combo:Int, score:Int, health:Float):Void
	{
		#if sys
		if (!pauseLogged) return;
		pauseLogged = false;
		row('resume', -1, '', null, combo, score, health, false, songTimeMs);
		#end
	}

	/**
	 * La vida llegó a cero. En modo experimento no termina el bloque: se registra el cruce
	 * y se aplica HEALTH_FLOOR. Puede ocurrir varias veces en un mismo bloque, y esa cuenta
	 * es en sí una medida de desempeño.
	 */
	public static function logFailureThreshold(songTimeMs:Float, combo:Int, score:Int, health:Float):Void
	{
		#if sys
		if (inFailure) return;
		inFailure = true;
		row('failure_threshold', -1, '', null, combo, score, health, false, songTimeMs);
		#end
	}

	/** Salida del estado de fracaso. El par entrada/salida da número de episodios y tiempo en fracaso. */
	public static function logFailureRecovered(songTimeMs:Float, combo:Int, score:Int, health:Float):Void
	{
		#if sys
		if (!inFailure) return;
		inFailure = false;
		row('failure_recovered', -1, '', null, combo, score, health, false, songTimeMs);
		#end
	}

	public static function endBlock(songTimeMs:Float, hits:Int, misses:Int, score:Int, accuracy:Float, health:Float):Void
	{
		#if sys
		if (out == null) return;
		row('block_end', -1, '', null, 0, score, health, false, songTimeMs);
		raw('# resumen aciertos=' + hits + ' errores=' + misses + ' score=' + score + ' precision=' + accuracy);
		closeBlock();
		#end
	}

	public static function closeBlock():Void
	{
		#if sys
		if (out == null) return;
		try
		{
			out.flush();
			out.close();
		}
		catch (e:Dynamic) {}
		out = null;
		#end
	}

	// ---------------------------------------------------------------- internos

	static function row(evento:String, direccion:Int, juicio:String, timingErrorMs:Null<Float>, combo:Int, score:Int, health:Float, sustain:Bool,
			songTimeMs:Float, version:String = '', segmento:Int = -1, ?notaMs:Null<Float>, detalle:String = ''):Void
	{
		#if sys
		if (out == null) return;
		seq++;
		var err:String = (timingErrorMs == null) ? '' : fmt(timingErrorMs);
		raw(seq
			+ ',' + Std.string(Date.now().getTime())
			+ ',' + fmt(songTimeMs)
			+ ',' + evento
			+ ',' + direccion
			+ ',' + juicio
			+ ',' + err
			+ ',' + combo
			+ ',' + score
			+ ',' + fmt(health)
			+ ',' + (sustain ? '1' : '0')
			+ ',' + version
			+ ',' + (segmento < 0 ? '' : Std.string(segmento))
			+ ',' + (notaMs == null ? '' : fmt(notaMs))
			+ ',' + detalle);
		#end
	}

	static function raw(line:String):Void
	{
		#if sys
		if (out == null) return;
		try
		{
			out.writeString(line + '\n');
			out.flush(); // flush por evento: pocas escrituras por segundo y los datos sobreviven a un crash
		}
		catch (e:Dynamic)
		{
			trace('[Telemetria] fallo al escribir -> $e');
		}
		#end
	}

	static function versionDe(note:Note):String
	{
		if (note == null || !note.extraData.exists('version')) return '';
		return Std.string(note.extraData.get('version'));
	}

	static function segmentoDe(note:Note):Int
	{
		if (note == null || !note.extraData.exists('segmento')) return -1;
		return Std.int(note.extraData.get('segmento'));
	}

	static function notaMs(note:Note):Null<Float>
		return note == null ? null : note.strumTime;

	/** Tres decimales, sin notación científica ni comas decimales. */
	static function fmt(v:Float):String
	{
		var r:Float = Math.round(v * 1000) / 1000;
		return StringTools.replace(Std.string(r), ',', '.');
	}

	static function safe(s:String):String
	{
		if (s == null) return 'na';
		var out:StringBuf = new StringBuf();
		for (i in 0...s.length)
		{
			var c:String = s.charAt(i);
			var code:Int = s.charCodeAt(i);
			var ok:Bool = (code >= 48 && code <= 57) // 0-9
				|| (code >= 65 && code <= 90) // A-Z
				|| (code >= 97 && code <= 122) // a-z
				|| c == '-' || c == '_';
			out.add(ok ? c : '-');
		}
		var r:String = out.toString();
		return r.length == 0 ? 'na' : r;
	}

	static function stamp():String
	{
		var d:Date = Date.now();
		return d.getFullYear() + two(d.getMonth() + 1) + two(d.getDate()) + '-' + two(d.getHours()) + two(d.getMinutes()) + two(d.getSeconds());
	}

	static inline function two(n:Int):String
		return (n < 10 ? '0' : '') + n;
}

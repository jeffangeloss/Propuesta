package backend;

import backend.IntercambioLogica;
import backend.IntercambioLogica.DecisionValida;
import backend.IntercambioLogica.SeccionMinima;
import backend.Song.SwagSong;
import objects.Note;
import states.PlayState;

/**
 * FNF-MOTIV [intercambio]: intercambio de versiones del chart en cortes de 8 compases.
 *
 * Al cargar la canción arma las tres versiones (Fácil, Media, Difícil) y las parte en
 * segmentos. La fila de aparición del motor (unspawnNotes) arranca solo con el segmento 0 en
 * Media. En el plazo de cada segmento siguiente, unos 2,25 s antes de su corte, lee
 * decision.json, elige la versión y agrega ese segmento a la fila. Como el segmento entra antes
 * de que alguna de sus notas llegue a la pantalla, nunca aparece una nota equivocada.
 *
 * La Media es el chart maestro: rival, eventos, cámara y velocidad salen solo de ella. Las
 * versiones difieren únicamente en las notas del jugador.
 */
class Intercambio
{
	public var activo(default, null):Bool = false;
	public var error(default, null):String = null;
	public var aplica(default, null):Bool = true;

	/** Tiempos en ms de la canción (incluyen noteOffset, igual que strumTime). */
	public var cortes(default, null):Array<Float> = [];
	public var plazos(default, null):Array<Float> = [];
	public var versiones(default, null):Array<Int> = [];

	var game:PlayState;
	var rival:Array<Array<Note>> = [];
	var jugador:Array<Array<Array<Note>>> = [[], [], []];
	var entregado:Int = 0;
	var cortesRegistrados:Int = -1;
	var anticipacionMs:Float = 0;

	public function new(game:PlayState)
		this.game = game;

	/**
	 * Arma las tres versiones a partir de las notas que generateSong construyó con el chart
	 * maestro. Devuelve la fila de aparición inicial. Si el intercambio no corresponde o falla,
	 * devuelve las notas tal cual y deja el motivo en `error`.
	 */
	public function preparar(cancion:String, notasMedia:Array<Note>):Array<Note>
	{
		Telemetry.cabeceraExtra = ['# modo_chart=fijo'];
		if (!Telemetry.experimentMode && !Telemetry.intercambioForzado) return notasMedia;

		// FNF-MOTIV [modo experimento]: una condición mal escrita no puede aplicar decisiones por descarte
		var errorCond:String = IntercambioLogica.errorCondicion(Telemetry.condition);
		if (errorCond != null) return fallar(errorCond, notasMedia);

		if (Difficulty.getString(PlayState.storyDifficulty, false).toLowerCase() != 'normal')
			return fallar('el intercambio necesita la dificultad Normal (Media) como chart maestro', notasMedia);

		var media:SwagSong = PlayState.SONG;
		var facil:SwagSong = null;
		var dificil:SwagSong = null;
		// Song.getChart lanza (no devuelve null) si falta el archivo o si el JSON está mal formado
		try
		{
			facil = Song.getChart(cancion + '-easy', cancion);
			dificil = Song.getChart(cancion + '-hard', cancion);
		}
		catch (e:Dynamic)
		{
			return fallar('no se pudieron leer los charts ' + cancion + '-easy y ' + cancion + '-hard (' + enUnaLinea(e) + ')', notasMedia);
		}
		if (facil == null || dificil == null)
			return fallar('faltan los charts ' + cancion + '-easy o ' + cancion + '-hard', notasMedia);
		if (facil.bpm != media.bpm || dificil.bpm != media.bpm)
			return fallar('las tres versiones deben tener el mismo BPM', notasMedia);
		for (e in game.eventNotes)
			if (e.event == 'Change Scroll Speed')
				return fallar('la canción cambia la velocidad a mitad (evento Change Scroll Speed) y los segmentos precargados no se reescalarían', notasMedia);

		var offset:Float = ClientPrefs.data.noteOffset;
		var secciones:Array<SeccionMinima> = [for (s in media.notes) {sectionBeats: s.sectionBeats, changeBPM: s.changeBPM, bpm: s.bpm}];
		var cortesChart:Array<Float> = IntercambioLogica.cortes(IntercambioLogica.iniciosDeSeccion(media.bpm, secciones));

		var porVersion:Array<Array<Note>> = [game.construirNotas(facil.notes, true), [for (n in notasMedia) if (n.mustPress) n],
			game.construirNotas(dificil.notes, true)];
		porVersion[0].sort(PlayState.sortByTime);
		porVersion[2].sort(PlayState.sortByTime);

		for (v in 0...3)
			for (n in porVersion[v])
				if (!n.isSustainNote && n.sustainLength > 0
					&& IntercambioLogica.segmentoDe(n.strumTime - offset, cortesChart) != IntercambioLogica.segmentoDe(n.strumTime - offset + n.sustainLength - 0.001, cortesChart))
				{
					destruirTodas(porVersion[0]);
					destruirTodas(porVersion[2]);
					return fallar('en ' + IntercambioLogica.NOMBRES[v] + ' una nota larga en ' + Math.round(n.strumTime - offset) + ' ms cruza un corte', notasMedia);
				}

		for (k in 0...cortesChart.length)
		{
			rival.push([]);
			for (v in 0...3) jugador[v].push([]);
		}
		for (n in notasMedia)
			if (!n.mustPress) rival[segmento(n, cortesChart, offset)].push(n);
		for (v in 0...3)
			for (n in porVersion[v])
			{
				var k:Int = segmento(n, cortesChart, offset);
				n.extraData.set('version', IntercambioLogica.NOMBRES[v]);
				n.extraData.set('segmento', k);
				jugador[v][k].push(n);
			}

		anticipacionMs = IntercambioLogica.anticipacion(game.playbackRate, game.songSpeed);
		cortes = [for (c in cortesChart) c + offset];
		plazos = [for (i in 0...cortesChart.length) i == 0 ? 0 : IntercambioLogica.plazo(cortesChart[i], offset, anticipacionMs)];
		versiones = [IntercambioLogica.MEDIA];
		aplica = Telemetry.condition != 'estatica';
		activo = true;

		Telemetry.cabeceraExtra = [
			'# modo_chart=intercambio',
			'# aplica_decisiones=' + (aplica ? '1' : '0'),
			'# version_inicial=media',
			'# compases_por_corte=' + IntercambioLogica.COMPASES_POR_CORTE,
			'# cortes_ms=' + [for (c in cortes) Std.string(Math.round(c * 1000) / 1000)].join(';'),
			'# plazos_ms=' + [for (p in plazos) Std.string(Math.round(p * 1000) / 1000)].join(';'),
			'# aparicion_ms=' + anticipacionMs,
			'# margen_ms=' + IntercambioLogica.MARGEN_MS,
			'# velocidad=' + game.songSpeed,
			'# huella_facil=' + huella(cancion + '-easy', cancion),
			'# huella_media=' + huella(cancion, cancion),
			'# huella_dificil=' + huella(cancion + '-hard', cancion)
		];
		// el segmento 0 siempre es Media, así que su Fácil y su Difícil no se usan nunca
		descartarOtras(0, IntercambioLogica.MEDIA);
		return mezclar(rival[0], jugador[IntercambioLogica.MEDIA][0]);
	}

	/** Se llama en cada cuadro, antes de que el motor pase notas a la pantalla. */
	public function actualizar(songPos:Float):Void
	{
		if (!activo || game.endingSong) return;
		while (entregado + 1 < cortes.length && songPos >= plazos[entregado + 1])
			entregar(entregado + 1, songPos);
		// el CSV del bloque se abre en startSong; con noteOffset negativo el corte 0 cae en el conteo
		if (game.startingSong) return;
		while (cortesRegistrados + 1 < cortes.length && songPos >= cortes[cortesRegistrados + 1])
		{
			cortesRegistrados++;
			Telemetry.logCorte(songPos, IntercambioLogica.NOMBRES[versiones[cortesRegistrados]], cortesRegistrados, game.combo, game.songScore, game.health);
		}
	}

	/** Libera las notas de las versiones y segmentos que nunca se entregaron. */
	public function destruir():Void
	{
		for (k in entregado + 1...rival.length) destruirTodas(rival[k]);
		for (v in 0...3)
			for (k in entregado + 1...jugador[v].length) destruirTodas(jugador[v][k]);
		activo = false;
	}

	function entregar(k:Int, songPos:Float):Void
	{
		var leida:Null<DecisionValida> = leerDecision(Telemetry.bloqueActual(), k);
		var recibida:String = (leida == null) ? 'sin_decision' : leida.decision;
		var v:Int = aplica ? IntercambioLogica.aplicar(versiones[k - 1], recibida) : IntercambioLogica.MEDIA;
		versiones[k] = v;
		insertarOrdenado(game.unspawnNotes, mezclar(rival[k], jugador[v][k]));
		descartarOtras(k, v);
		entregado = k;
		var margen:Float = cortes[k] - anticipacionMs - songPos;
		Telemetry.logDecision(songPos, IntercambioLogica.NOMBRES[v], k, IntercambioLogica.detalle([
			['recibida', recibida],
			['fuente', leida == null ? '' : leida.fuente],
			['seq', leida == null ? '' : Std.string(leida.seq)],
			['margen_ms', Std.string(Math.round(margen))],
			['aplicada', aplica ? '1' : '0']
		]), game.combo, game.songScore, game.health);
	}

	/** Destruye las notas del jugador del segmento k en las versiones distintas de la elegida. */
	function descartarOtras(k:Int, elegida:Int):Void
	{
		for (otra in 0...3)
			if (otra != elegida)
			{
				destruirTodas(jugador[otra][k]);
				jugador[otra][k] = [];
			}
	}

	function leerDecision(bloque:String, segmento:Int):Null<DecisionValida>
	{
		#if sys
		try
		{
			var ruta:String = Telemetry.baseDir() + '/decision.json';
			if (!FileSystem.exists(ruta)) return null;
			return IntercambioLogica.validarDecision(haxe.Json.parse(File.getContent(ruta)), bloque, segmento);
		}
		catch (e:Dynamic)
		{
			return null;
		}
		#else
		return null;
		#end
	}

	function fallar(motivo:String, notas:Array<Note>):Array<Note>
	{
		error = motivo;
		activo = false;
		Telemetry.cabeceraExtra = ['# modo_chart=fijo', '# error_intercambio=' + motivo];
		trace('[Intercambio] ' + motivo);
		return notas;
	}

	static function segmento(n:Note, cortesChart:Array<Float>, offset:Float):Int
	{
		var cabeza:Note = (n.isSustainNote && n.parent != null) ? n.parent : n;
		return IntercambioLogica.segmentoDe(cabeza.strumTime - offset, cortesChart);
	}

	/** Une dos listas ordenadas por tiempo sin reordenar cada una (el sort del motor no es estable). */
	static function mezclar(a:Array<Note>, b:Array<Note>):Array<Note>
	{
		var r:Array<Note> = [];
		var i:Int = 0;
		var j:Int = 0;
		while (i < a.length || j < b.length)
		{
			if (j >= b.length || (i < a.length && a[i].strumTime <= b[j].strumTime)) r.push(a[i++]);
			else r.push(b[j++]);
		}
		return r;
	}

	/**
	 * Agrega a la fila notas ya ordenadas sin romper su orden. Casi siempre caen al final, pero la
	 * cola de una nota larga del rival viaja con el segmento de su cabeza y puede seguir en la fila
	 * después del corte siguiente. El bucle de aparición solo mira el primer elemento de la fila.
	 */
	static function insertarOrdenado(fila:Array<Note>, nuevas:Array<Note>):Void
	{
		for (n in nuevas)
		{
			var i:Int = fila.length;
			while (i > 0 && fila[i - 1].strumTime > n.strumTime) i--;
			fila.insert(i, n);
		}
	}

	static function enUnaLinea(e:Dynamic):String
		return StringTools.replace(StringTools.replace(Std.string(e), '\r', ' '), '\n', ' ');

	static function destruirTodas(notas:Array<Note>):Void
		for (n in notas) n.destroy();

	static function huella(archivo:String, carpeta:String):String
	{
		try
		{
			var ruta:String = Paths.json(Paths.formatToSongPath(carpeta) + '/' + Paths.formatToSongPath(archivo));
			var texto:String = null;
			#if MODS_ALLOWED
			if (FileSystem.exists(ruta)) texto = File.getContent(ruta);
			#end
			if (texto == null) texto = lime.utils.Assets.getText(ruta);
			return (texto == null) ? '' : haxe.crypto.Sha256.encode(texto);
		}
		catch (e:Dynamic)
		{
			return '';
		}
	}
}

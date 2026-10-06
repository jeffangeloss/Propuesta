import backend.IntercambioLogica as L;
import backend.IntercambioLogica.SeccionMinima;

/** Pruebas de la lógica pura del intercambio. Se corren con tesis/pruebas/correr_pruebas.sh */
class TestIntercambio
{
	static var fallas:Int = 0;
	static var total:Int = 0;

	static function ok(cond:Bool, nombre:String):Void
	{
		total++;
		if (!cond) { fallas++; Sys.println('FALLA  ' + nombre); }
	}

	static function cerca(a:Float, b:Float, nombre:String):Void
		ok(Math.abs(a - b) < 1e-6, nombre + ' (obtuvo ' + a + ', esperaba ' + b + ')');

	static function secciones(n:Int):Array<SeccionMinima>
		return [for (i in 0...n) {sectionBeats: 4.0}];

	static function main():Void
	{
		// cortes a BPM fijo: 120 BPM, 4/4 -> 2000 ms por sección, 16 000 ms por corte
		var ini = L.iniciosDeSeccion(120, secciones(20));
		cerca(ini[1], 2000, 'sección de 2000 ms a 120 BPM');
		cerca(ini[20], 40000, 'final de 20 secciones');
		var c = L.cortes(ini);
		ok(c.length == 3, 'tres cortes en 20 secciones (0, 8, 16)');
		cerca(c[1], 16000, 'segundo corte a 16 s');
		cerca(c[2], 32000, 'tercer corte a 32 s');

		// cambio de BPM a mitad: 4 secciones a 100 y luego 200 BPM
		var mix:Array<SeccionMinima> = secciones(10);
		mix[4] = {sectionBeats: 4.0, changeBPM: true, bpm: 200.0};
		var ini2 = L.iniciosDeSeccion(100, mix);
		cerca(ini2[4], 4 * 2400, 'cuatro secciones a 100 BPM');
		cerca(ini2[8], 4 * 2400 + 4 * 1200, 'cuatro más a 200 BPM');
		cerca(L.cortes(ini2)[1], 14400, 'corte con cambio de BPM');

		// sectionBeats nulo cuenta como 4
		var nulo:Array<SeccionMinima> = [{sectionBeats: null}];
		cerca(L.iniciosDeSeccion(120, nulo)[1], 2000, 'sectionBeats nulo');

		// segmentos
		ok(L.segmentoDe(-50, c) == 0, 'nota antes del inicio');
		ok(L.segmentoDe(0, c) == 0, 'nota en 0');
		ok(L.segmentoDe(15999.9, c) == 0, 'justo antes del corte');
		ok(L.segmentoDe(16000, c) == 1, 'en el corte pertenece al siguiente');
		ok(L.segmentoDe(99999, c) == 2, 'después del último corte');

		// anticipación y plazo
		cerca(L.anticipacion(1, 1.3), 2000, 'velocidad >= 1');
		cerca(L.anticipacion(1, 0.5), 4000, 'velocidad < 1 alarga');
		cerca(L.anticipacion(1.5, 2), 3000, 'playbackRate multiplica');
		cerca(L.plazo(16000, 0, 2000), 13750, 'plazo 2,25 s antes');
		cerca(L.plazo(16000, 20, 2000), 13770, 'noteOffset corre el plazo');

		// aplicar
		ok(L.aplicar(L.MEDIA, 'sube') == L.DIFICIL, 'sube');
		ok(L.aplicar(L.DIFICIL, 'sube') == L.DIFICIL, 'no pasa de Difícil');
		ok(L.aplicar(L.FACIL, 'baja') == L.FACIL, 'no baja de Fácil');
		ok(L.aplicar(L.MEDIA, 'queda') == L.MEDIA, 'queda');
		ok(L.aplicar(L.MEDIA, 'cualquiera') == L.MEDIA, 'desconocida mantiene');

		// validar decisión
		var bueno = haxe.Json.parse('{"bloque":"P01_adaptativa_roses_x","segmento":3,"decision":"sube","seq":17,"fuente":"simulado","unix_ms":1790108400123}');
		var v = L.validarDecision(bueno, 'P01_adaptativa_roses_x', 3);
		ok(v != null && v.decision == 'sube' && v.seq == 17 && v.fuente == 'simulado', 'decisión válida');
		ok(L.validarDecision(bueno, 'P01_adaptativa_roses_x', 4) == null, 'otro segmento');
		ok(L.validarDecision(bueno, 'otro_bloque', 3) == null, 'otro bloque');
		ok(L.validarDecision(haxe.Json.parse('{"bloque":"b","segmento":1,"decision":"arriba"}'), 'b', 1) == null, 'decisión inválida');
		ok(L.validarDecision(haxe.Json.parse('{"bloque":"b","segmento":"1","decision":"sube"}'), 'b', 1) == null, 'segmento como texto');
		ok(L.validarDecision(haxe.Json.parse('{"bloque":"b","decision":"sube"}'), 'b', 1) == null, 'falta segmento');
		ok(L.validarDecision(null, 'b', 1) == null, 'nulo');
		var minima = L.validarDecision(haxe.Json.parse('{"bloque":"b","segmento":1,"decision":"baja"}'), 'b', 1);
		ok(minima != null && minima.seq == -1 && minima.fuente == '', 'campos opcionales');

		// detalle
		ok(L.detalle([['recibida', 'sube'], ['margen_ms', '412']]) == 'recibida=sube;margen_ms=412', 'detalle');
		ok(L.detalle([['fuente', 'a;b,c']]) == 'fuente=a b c', 'detalle sin separadores');

		// condición de sesion.txt: solo «adaptativa» o «estatica», escritas exactamente así
		ok(L.errorCondicion('adaptativa') == null, 'condición adaptativa válida');
		ok(L.errorCondicion('estatica') == null, 'condición estatica válida');
		for (mala in ['Estatica', 'estática', 'ESTATICA', 'Adaptativa', 'adaptativo', 'practica', '', ' estatica', 'estatica ', 'adaptativa;estatica', null])
			ok(L.errorCondicion(mala) != null, 'condición rechazada: «' + mala + '»');
		var motivo = L.errorCondicion('practica');
		ok(motivo.indexOf('practica') >= 0 && motivo.indexOf('adaptativa') >= 0 && motivo.indexOf('estatica') >= 0,
			'el motivo nombra la condición recibida y las dos permitidas');

		Sys.println((total - fallas) + ' de ' + total + ' pruebas pasan');
		Sys.exit(fallas == 0 ? 0 : 1);
	}
}

import 'package:cloud_firestore/cloud_firestore.dart';

const tiposIdentificacionMenor = [
  'Registro Civil',
  'Tarjeta de Identidad',
  'Cédula de Extranjería',
  'Pasaporte',
  'No tiene documento',
];

const generos = ['Masculino', 'Femenino'];

/// Valores posibles de `estadoRegistro`. "Graduado" sigue siendo un
/// ajuste manual (fuera de esta lista de gestión de asistencia — no
/// hay flujo en la app para volver a poner "Activo" a un niño
/// graduado). "Inactivo" (2026-08-21, pedido de Rafael) es el que se
/// puede alternar desde una `Gestion` — para un niño que dejó de venir
/// y se confirmó que no va a volver (ej. se mudó de ciudad), sin
/// borrarlo ni perder su historial.
const estadosRegistroGestionables = ['Activo', 'Inactivo'];

/// Los 5 grupos/aulas del ministerio infantil, en orden de edad.
const gruposEdad = ['José', 'David', 'Judá', 'Daniel', 'Santiago'];

/// El rango de edad que representa cada grupo (para mostrar junto al
/// nombre del grupo en las pantallas que lo requieran) — debe quedar
/// sincronizado con [grupoParaEdad].
const rangoEdadPorGrupo = {
  'José': '2 años',
  'David': '3-4 años',
  'Judá': '5-6 años',
  'Daniel': '7-8 años',
  'Santiago': '9-10 años',
};

const parentescos = [
  'Padre',
  'Madre',
  'Tío/a',
  'Abuelo/a',
  'Acudiente Autorizado',
];

/// Rango de edad que recibe el ministerio infantil (RocaKids no recibe
/// bebés menores de 2 años, ni preadolescentes de 11 años o más).
const edadMinimaRegistro = 2;
const edadMaximaRegistro = 10;

/// Edad actual (en años cumplidos) a partir de la fecha de nacimiento.
int calcularEdad(DateTime fechaNacimiento) {
  final ahora = DateTime.now();
  var edad = ahora.year - fechaNacimiento.year;
  if (ahora.month < fechaNacimiento.month ||
      (ahora.month == fechaNacimiento.month && ahora.day < fechaNacimiento.day)) {
    edad--;
  }
  return edad;
}

/// Grupo/aula del ministerio infantil al que pertenecería un niño HOY,
/// según su edad actual. A propósito no se guarda en el registro del
/// menor ni en ningún lado: la edad (y por lo tanto el grupo) cambia con
/// el tiempo, así que debe recalcularse cada vez que haga falta (ej. al
/// registrar el ingreso), no quedar fijada desde el momento del registro.
String? grupoParaEdad(int edad) {
  if (edad == 2) return 'José';
  if (edad >= 3 && edad <= 4) return 'David';
  if (edad >= 5 && edad <= 6) return 'Judá';
  if (edad >= 7 && edad <= 8) return 'Daniel';
  if (edad >= 9 && edad <= 10) return 'Santiago';
  return null;
}

/// true si el cumpleaños de [fechaNacimiento] (comparando solo mes y
/// día, sin importar el año) cayó en alguno de los últimos 7 días
/// (incluyendo hoy). Base de la vista "Cumpleaños" y del aviso al
/// registrar el ingreso de un niño (2026-08-18, pedido de Rafael).
bool cumpleEnUltimaSemana(DateTime fechaNacimiento, {DateTime? hoy}) =>
    diasDesdeCumpleanos(fechaNacimiento, hoy: hoy) != null;

/// Cuántos días atrás cayó el cumpleaños de este año (0 = hoy), o `null`
/// si no cayó en los últimos 7 días. Sirve para mostrar "Cumple hoy" /
/// "Cumplió hace N días".
int? diasDesdeCumpleanos(DateTime fechaNacimiento, {DateTime? hoy}) {
  final ahora = hoy ?? DateTime.now();
  for (var i = 0; i < 7; i++) {
    final dia = ahora.subtract(Duration(days: i));
    if (dia.month == fechaNacimiento.month && dia.day == fechaNacimiento.day) {
      return i;
    }
  }
  return null;
}

/// "MM-DD" de una fecha, sin importar el año — campo derivado que se
/// guarda junto a `fechaNacimiento` (en `ninos` y `usuarios`) para poder
/// consultar "quién cumple esta semana" con un `where` acotado en vez de
/// traer la colección completa y filtrar del lado del cliente
/// (encontrado 2026-08-19: "Cumpleaños niños/servidores" lento en
/// celular con ~400+ documentos).
String mesDiaDe(DateTime fecha) =>
    '${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

/// Los 7 valores de "MM-DD" que cuentan como "esta semana" (hoy y los 6
/// días anteriores) — mismo criterio exacto que [diasDesdeCumpleanos],
/// para usar en un `where('mesDiaNacimiento', whereIn: ...)`.
List<String> mesDiaUltimaSemana({DateTime? hoy}) {
  final ahora = hoy ?? DateTime.now();
  return [for (var i = 0; i < 7; i++) mesDiaDe(ahora.subtract(Duration(days: i)))];
}

/// Genera la llave interna del SOP (§3.2) cuando el menor no tiene
/// número de documento: fechaNacimiento-PRIMERNOMBRE-PRIMERAPELLIDO.
String generarLlaveInterna({
  required DateTime fechaNacimiento,
  required String nombres,
  required String apellidos,
}) {
  final fecha =
      '${fechaNacimiento.year.toString().padLeft(4, '0')}'
      '${fechaNacimiento.month.toString().padLeft(2, '0')}'
      '${fechaNacimiento.day.toString().padLeft(2, '0')}';
  final primerNombre = nombres.trim().split(RegExp(r'\s+')).first.toUpperCase();
  final primerApellido = apellidos.trim().split(RegExp(r'\s+')).first.toUpperCase();
  return '$fecha-$primerNombre-$primerApellido';
}

class Nino {
  final String documentoIdentificacion; // ID del documento en Firestore
  final String tipoIdentificacion;
  final String identificacionMenor;
  final String nombres;
  final String apellidos;
  final DateTime fechaNacimiento;
  final String genero;
  final String estadoRegistro;
  final bool alertaMedicaFlag;
  final String condicionMedica;
  final bool autorizoFotoFlag;
  final String fotoUrl;
  // Si el niño está ahora mismo adentro (última Entrada sin Salida
  // todavía) — lo mantiene `AuthService.registrarMovimiento()` en el
  // mismo batch atómico que crea cada `Registro`. Es la fuente de verdad
  // real de "¿ya entró hoy?" (misma que usa `firestore.rules` para
  // bloquear una segunda Entrada) — a propósito NO se deriva del último
  // movimiento en `registros`, porque los 3738 registros históricos
  // migrados (2026-08-19) se importaron todos como 'Entrada' sin ninguna
  // 'Salida', así que "el último movimiento de toda la historia" de un
  // niño puede ser una Entrada de hace meses.
  final bool presente;
  // Denormalizado junto con la subcolección `no_autorizados` (ver
  // AuthService.agregarNoAutorizado()/eliminarNoAutorizado()) para que
  // el check-in y "Menores Recibidos" puedan mostrar la advertencia sin
  // una consulta extra por niño — ambas pantallas ya cargan el `Nino`
  // completo de todas formas.
  final bool tieneNoAutorizados;
  // Total de Entradas de toda la historia y fecha de la más reciente —
  // mantenidos por la Cloud Function `actualizarResumenMensual` en cada
  // Entrada NUEVA (`app/functions/index.js`), y calculados una sola vez
  // para el histórico con `AuthService.backfillEstadisticasAsistencia()`
  // (ver docs/estado-proyecto.md). Alimentan el reporte "Niños que
  // dejaron de asistir" del Dashboard: si el niño registra una Entrada
  // nueva, `ultimaAsistencia` se actualiza de inmediato y sale de ese
  // reporte en la siguiente consulta — no hay ningún contador separado
  // que reiniciar a mano.
  final int totalEntradas;
  final DateTime? ultimaAsistencia;

  const Nino({
    required this.documentoIdentificacion,
    required this.tipoIdentificacion,
    required this.identificacionMenor,
    required this.nombres,
    required this.apellidos,
    required this.fechaNacimiento,
    required this.genero,
    required this.estadoRegistro,
    required this.alertaMedicaFlag,
    required this.condicionMedica,
    required this.autorizoFotoFlag,
    this.fotoUrl = '',
    this.presente = false,
    this.tieneNoAutorizados = false,
    this.totalEntradas = 0,
    this.ultimaAsistencia,
  });

  String get nombreCompleto => '$nombres $apellidos';

  Map<String, dynamic> toFirestore() => {
    'documentoIdentificacion': documentoIdentificacion,
    'tipoIdentificacion': tipoIdentificacion,
    'identificacionMenor': identificacionMenor,
    'nombres': nombres,
    'apellidos': apellidos,
    'fechaNacimiento': Timestamp.fromDate(fechaNacimiento),
    'mesDiaNacimiento': mesDiaDe(fechaNacimiento),
    'genero': genero,
    'estadoRegistro': estadoRegistro,
    'alertaMedicaFlag': alertaMedicaFlag,
    'condicionMedica': condicionMedica,
    'autorizoFotoFlag': autorizoFotoFlag,
    'fotoUrl': fotoUrl,
    'tieneNoAutorizados': tieneNoAutorizados,
    'totalEntradas': totalEntradas,
    'ultimaAsistencia': ultimaAsistencia != null
        ? Timestamp.fromDate(ultimaAsistencia!)
        : null,
  };

  factory Nino.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['fechaNacimiento'];
    final ultima = data['ultimaAsistencia'];
    return Nino(
      documentoIdentificacion: id,
      tipoIdentificacion: data['tipoIdentificacion'] as String? ?? '',
      identificacionMenor: data['identificacionMenor'] as String? ?? '',
      nombres: data['nombres'] as String? ?? '',
      apellidos: data['apellidos'] as String? ?? '',
      fechaNacimiento: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
      genero: data['genero'] as String? ?? '',
      estadoRegistro: data['estadoRegistro'] as String? ?? '',
      alertaMedicaFlag: data['alertaMedicaFlag'] as bool? ?? false,
      condicionMedica: data['condicionMedica'] as String? ?? '',
      autorizoFotoFlag: data['autorizoFotoFlag'] as bool? ?? false,
      fotoUrl: data['fotoUrl'] as String? ?? '',
      presente: data['presente'] as bool? ?? false,
      tieneNoAutorizados: data['tieneNoAutorizados'] as bool? ?? false,
      totalEntradas: data['totalEntradas'] as int? ?? 0,
      ultimaAsistencia: ultima is Timestamp ? ultima.toDate() : null,
    );
  }
}

/// Copia mínima de un niño (solo nombre y fecha de nacimiento) que
/// cualquier cuenta logueada puede listar para buscarlo por nombre al
/// vincularlo — a propósito NO incluye foto, documento, ni información
/// médica, para que alguien sin ningún vínculo real con el niño no pueda
/// "navegar" esos datos sensibles solo con el nombre. Vive en la
/// colección `ninos_busqueda`, escrita junto con `ninos` en el mismo
/// batch (ver [Nino]).
class NinoBusqueda {
  final String documentoIdentificacion;
  final String nombres;
  final String apellidos;
  final DateTime fechaNacimiento;

  const NinoBusqueda({
    required this.documentoIdentificacion,
    required this.nombres,
    required this.apellidos,
    required this.fechaNacimiento,
  });

  String get nombreCompleto => '$nombres $apellidos';

  Map<String, dynamic> toFirestore() => {
    'nombres': nombres,
    'apellidos': apellidos,
    'fechaNacimiento': Timestamp.fromDate(fechaNacimiento),
  };

  factory NinoBusqueda.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['fechaNacimiento'];
    return NinoBusqueda(
      documentoIdentificacion: id,
      nombres: data['nombres'] as String? ?? '',
      apellidos: data['apellidos'] as String? ?? '',
      fechaNacimiento: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
    );
  }

  /// Compara sin distinguir mayúsculas/acentos, para que buscar "jose"
  /// también encuentre a "José".
  bool coincideBusqueda(String query) =>
      _normalizar(nombreCompleto).contains(_normalizar(query));
}

const _acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n'};

String _normalizar(String texto) {
  final buffer = StringBuffer();
  for (final char in texto.toLowerCase().split('')) {
    buffer.write(_acentos[char] ?? char);
  }
  return buffer.toString();
}

class NinoAcudiente {
  final String id;
  final String fkIdNino;
  final String fkIdAcudiente;
  final String parentescoTipo;
  final String autorizacionFormulario;
  final String autorizacionImagen;
  final bool esRepresentanteLegalFlag;

  const NinoAcudiente({
    required this.id,
    required this.fkIdNino,
    required this.fkIdAcudiente,
    required this.parentescoTipo,
    required this.autorizacionFormulario,
    required this.autorizacionImagen,
    required this.esRepresentanteLegalFlag,
  });

  Map<String, dynamic> toFirestore() => {
    'fk_idNino': fkIdNino,
    'fk_idAcudiente': fkIdAcudiente,
    'parentescoTipo': parentescoTipo,
    'autorizacionFormulario': autorizacionFormulario,
    'autorizacionImagen': autorizacionImagen,
    'esRepresentanteLegalFlag': esRepresentanteLegalFlag,
  };

  factory NinoAcudiente.fromFirestore(String id, Map<String, dynamic> data) {
    return NinoAcudiente(
      id: id,
      fkIdNino: data['fk_idNino'] as String? ?? '',
      fkIdAcudiente: data['fk_idAcudiente'] as String? ?? '',
      parentescoTipo: data['parentescoTipo'] as String? ?? '',
      autorizacionFormulario: data['autorizacionFormulario'] as String? ?? '',
      autorizacionImagen: data['autorizacionImagen'] as String? ?? '',
      esRepresentanteLegalFlag: data['esRepresentanteLegalFlag'] as bool? ?? false,
    );
  }
}

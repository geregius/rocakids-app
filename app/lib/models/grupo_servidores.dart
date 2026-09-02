import 'package:cloud_firestore/cloud_firestore.dart';

/// Nombre en español de un día de la semana (`DateTime.monday`..`sunday`,
/// 1-7) — para mostrar "cada Domingo", elegir el día en el formulario de
/// categoría, etc.
const _nombresDias = {
  1: 'Lunes',
  2: 'Martes',
  3: 'Miércoles',
  4: 'Jueves',
  5: 'Viernes',
  6: 'Sábado',
  7: 'Domingo',
};
String nombreDiaSemana(int dia) => _nombresDias[dia] ?? '';

/// Cómo se decide quién sirve en cada ocasión de una categoría
/// (2026-09-02, pedido de Rafael — "Programación de Servidores" etapa
/// 2, rotación automática):
/// - `semanal`: cae en un día fijo de la semana (ej. cada domingo) —
///   el sistema calcula solo, en orden, qué grupo le toca cada vez, a
///   partir de un punto de partida que Rafael fija una sola vez
///   ([CategoriaProgramacion.fechaReferenciaRotacion] +
///   [CategoriaProgramacion.grupoReferenciaId]).
/// - `manual`: no cae en un día fijo (ej. Casa2 es "un viernes al
///   mes", Ayunos "una vez al mes") — se programa cada ocasión a mano
///   (`servicios_programados`), aunque el sistema SUGIERE el siguiente
///   grupo en el orden de rotación para no tener que decidirlo desde
///   cero cada vez.
enum TipoRotacion {
  semanal,
  manual;

  static TipoRotacion fromString(String? v) =>
      v == 'semanal' ? TipoRotacion.semanal : TipoRotacion.manual;
}

/// Una categoría de programación de servidores (ej. "Domingos",
/// "Miércoles") — los "servicios" en los que se organizan equipos de
/// servidores que rotan. Distinto de [serviciosDisponibles]
/// (`models/registro.dart`), que son los servicios donde se registra
/// la asistencia de los NIÑOS — acá el objeto es agrupar SERVIDORES en
/// equipos, no niños en check-in.
///
/// **2026-08-31, ajuste de Rafael el mismo día:** empezaron como una
/// lista fija en el código (`Domingos`, `Miércoles`, `Casa2`,
/// `Ayunos`) — Rafael pidió poder crear categorías nuevas también, así
/// que pasaron a esta colección propia (`categorias_programacion`),
/// igual de administrable que los grupos (mismo permiso,
/// `puedeGestionarProgramacion`).
class CategoriaProgramacion {
  final String id;
  final String nombre;
  final TipoRotacion tipoRotacion;
  final int? diaSemana; // 1=lunes...7=domingo (DateTime.monday..sunday), solo si es semanal
  final DateTime? fechaReferenciaRotacion; // solo si es semanal y ya se configuró el punto de partida
  final String? grupoReferenciaId; // qué grupo sirve en fechaReferenciaRotacion
  final DateTime creadoEn;

  const CategoriaProgramacion({
    required this.id,
    required this.nombre,
    required this.tipoRotacion,
    this.diaSemana,
    this.fechaReferenciaRotacion,
    this.grupoReferenciaId,
    required this.creadoEn,
  });

  Map<String, dynamic> toFirestore() => {
    'nombre': nombre,
    'tipoRotacion': tipoRotacion.name,
    if (diaSemana != null) 'diaSemana': diaSemana,
  };

  factory CategoriaProgramacion.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['creadoEn'];
    final fechaRef = data['fechaReferenciaRotacion'];
    return CategoriaProgramacion(
      id: id,
      nombre: data['nombre'] as String? ?? '',
      tipoRotacion: TipoRotacion.fromString(data['tipoRotacion'] as String?),
      diaSemana: data['diaSemana'] as int?,
      fechaReferenciaRotacion: fechaRef is Timestamp ? fechaRef.toDate() : null,
      grupoReferenciaId: data['grupoReferenciaId'] as String?,
      creadoEn: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
    );
  }
}

/// Un grupo/equipo de servidores dentro de una categoría (ej. "Grupo 2"
/// de "Domingos") — quiénes lo integran, para poder organizar turnos.
/// Solo administrador y líder de ministerio pueden crearlos/editarlos
/// (`RolUsuario.puedeGestionarProgramacion`, ver `usuario_app.dart` y
/// `firestore.rules`).
class GrupoServidores {
  final String id;
  final String categoria;
  final String nombre;
  final List<String> fkIdsServidores;
  // Posición en la rotación de su categoría (0 = primero) — 2026-09-02,
  // necesario para calcular "a quién le toca" en orden. Por defecto
  // queda al final (según cuántos grupos ya tenía la categoría al
  // crearse), con botones de mover arriba/abajo para corregirlo a mano
  // si hace falta.
  final int orden;
  final DateTime creadoEn;

  const GrupoServidores({
    required this.id,
    required this.categoria,
    required this.nombre,
    required this.fkIdsServidores,
    required this.orden,
    required this.creadoEn,
  });

  Map<String, dynamic> toFirestore() => {
    'categoria': categoria,
    'nombre': nombre,
    'fkIdsServidores': fkIdsServidores,
    'orden': orden,
  };

  factory GrupoServidores.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['creadoEn'];
    return GrupoServidores(
      id: id,
      categoria: data['categoria'] as String? ?? '',
      nombre: data['nombre'] as String? ?? '',
      fkIdsServidores: (data['fkIdsServidores'] as List?)?.cast<String>() ?? [],
      orden: data['orden'] as int? ?? 0,
      creadoEn: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
    );
  }
}

/// Una ocasión programada a mano de una categoría `manual` (Casa2,
/// Ayunos) — ej. "el Casa2 del 12 de septiembre lo sirve el Grupo 2".
/// 2026-09-02, pedido de Rafael.
class ServicioProgramado {
  final String id;
  final String categoria;
  final DateTime fecha;
  final String grupoId;
  final DateTime creadoEn;

  const ServicioProgramado({
    required this.id,
    required this.categoria,
    required this.fecha,
    required this.grupoId,
    required this.creadoEn,
  });

  Map<String, dynamic> toFirestore() => {
    'categoria': categoria,
    'fecha': Timestamp.fromDate(fecha),
    'grupoId': grupoId,
  };

  factory ServicioProgramado.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['fecha'];
    final creado = data['creadoEn'];
    return ServicioProgramado(
      id: id,
      categoria: data['categoria'] as String? ?? '',
      fecha: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
      grupoId: data['grupoId'] as String? ?? '',
      creadoEn: creado is Timestamp ? creado.toDate() : DateTime.now(),
    );
  }
}

/// [gruposOrdenados] ya debe venir ordenado por [GrupoServidores.orden].
/// Calcula qué grupo sirve en [fechaObjetivo], contando cuántas semanas
/// pasaron desde [fechaReferencia] (donde sirvió el grupo
/// [grupoReferenciaId]) y avanzando esa cantidad de posiciones en la
/// rotación, en círculo. [fechaObjetivo] y [fechaReferencia] deben caer
/// en el mismo día de la semana — si no, el resultado no tiene sentido
/// (validado por quien llama, ver `diaSemana` de la categoría).
///
/// `null` si no hay grupos, o si el grupo de referencia ya no existe
/// (se borró) — en ese caso hace falta reconfigurar el punto de
/// partida.
GrupoServidores? grupoQueSirve({
  required List<GrupoServidores> gruposOrdenados,
  required DateTime fechaReferencia,
  required String grupoReferenciaId,
  required DateTime fechaObjetivo,
}) {
  if (gruposOrdenados.isEmpty) return null;
  final indiceReferencia = gruposOrdenados.indexWhere((g) => g.id == grupoReferenciaId);
  if (indiceReferencia == -1) return null;
  final diasDiff = fechaObjetivo.difference(fechaReferencia).inDays;
  final semanasDiff = diasDiff ~/ 7;
  final total = gruposOrdenados.length;
  final indiceObjetivo = ((indiceReferencia + semanasDiff) % total + total) % total;
  return gruposOrdenados[indiceObjetivo];
}

/// El próximo grupo sugerido para una categoría `manual` (Casa2,
/// Ayunos): el siguiente en el orden después del grupo que sirvió en
/// [ultimoServicio] (el `ServicioProgramado` más reciente de esa
/// categoría), o el primero de la rotación si todavía no se ha
/// programado ninguno.
GrupoServidores? siguienteGrupoSugerido({
  required List<GrupoServidores> gruposOrdenados,
  ServicioProgramado? ultimoServicio,
}) {
  if (gruposOrdenados.isEmpty) return null;
  if (ultimoServicio == null) return gruposOrdenados.first;
  final indiceUltimo = gruposOrdenados.indexWhere((g) => g.id == ultimoServicio.grupoId);
  if (indiceUltimo == -1) return gruposOrdenados.first;
  return gruposOrdenados[(indiceUltimo + 1) % gruposOrdenados.length];
}

/// Próxima fecha (incluyendo hoy) que cae en [diaSemana]
/// (`DateTime.monday`..`DateTime.sunday`) a partir de [desde].
DateTime proximaFechaDia(int diaSemana, {DateTime? desde}) {
  final hoy = desde ?? DateTime.now();
  final base = DateTime(hoy.year, hoy.month, hoy.day);
  final diff = (diaSemana - base.weekday) % 7;
  return base.add(Duration(days: diff < 0 ? diff + 7 : diff));
}

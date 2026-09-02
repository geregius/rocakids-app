import 'package:cloud_firestore/cloud_firestore.dart';

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
  final DateTime creadoEn;

  const CategoriaProgramacion({
    required this.id,
    required this.nombre,
    required this.creadoEn,
  });

  Map<String, dynamic> toFirestore() => {'nombre': nombre};

  factory CategoriaProgramacion.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['creadoEn'];
    return CategoriaProgramacion(
      id: id,
      nombre: data['nombre'] as String? ?? '',
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
  final DateTime creadoEn;

  const GrupoServidores({
    required this.id,
    required this.categoria,
    required this.nombre,
    required this.fkIdsServidores,
    required this.creadoEn,
  });

  Map<String, dynamic> toFirestore() => {
    'categoria': categoria,
    'nombre': nombre,
    'fkIdsServidores': fkIdsServidores,
  };

  factory GrupoServidores.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['creadoEn'];
    return GrupoServidores(
      id: id,
      categoria: data['categoria'] as String? ?? '',
      nombre: data['nombre'] as String? ?? '',
      fkIdsServidores: (data['fkIdsServidores'] as List?)?.cast<String>() ?? [],
      creadoEn: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
    );
  }
}

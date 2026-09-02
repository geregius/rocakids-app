import 'package:cloud_firestore/cloud_firestore.dart';

/// Categorías fijas de programación de servidores (2026-08-31, pedido
/// de Rafael) — los "servicios" en los que se organizan equipos de
/// servidores que rotan. Distinto de [serviciosDisponibles]
/// (`models/registro.dart`), que son los servicios donde se registra
/// la asistencia de los NIÑOS — acá el objeto es agrupar SERVIDORES en
/// equipos, no niños en check-in.
const categoriasProgramacion = ['Domingos', 'Miércoles', 'Casa2', 'Ayunos'];

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

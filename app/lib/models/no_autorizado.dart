import 'package:cloud_firestore/cloud_firestore.dart';

/// Alguien que NO debe tener contacto con un niño puntual — ej. un
/// familiar en medio de una disputa de custodia, o alguien con una
/// orden de alejamiento. A propósito es texto libre (nombre/documento)
/// y no un vínculo a una cuenta: casi nunca esta persona está
/// registrada como acudiente en RocaKids. Vive en la subcolección
/// `ninos/{ninoId}/no_autorizados`. Solo liderazgo (admin/columna/líder
/// de ministerio) o el padre/madre vinculado al niño pueden
/// agregar/quitar entradas (decisión de Rafael, 2026-08-21) — ver
/// `esPadreOMadreDe()`/`puedeVerInfoLiderazgo()` en firestore.rules.
class NoAutorizado {
  final String id;
  final String nombre;
  final String documento;
  final String motivo;
  final String fkIdRegistradoPor;
  final String nombreRegistradoPor;
  final DateTime fechaRegistro;

  const NoAutorizado({
    required this.id,
    required this.nombre,
    required this.documento,
    required this.motivo,
    required this.fkIdRegistradoPor,
    required this.nombreRegistradoPor,
    required this.fechaRegistro,
  });

  Map<String, dynamic> toFirestore() => {
    'nombre': nombre,
    'documento': documento,
    'motivo': motivo,
    'fkIdRegistradoPor': fkIdRegistradoPor,
    'nombreRegistradoPor': nombreRegistradoPor,
    'fechaRegistro': Timestamp.fromDate(fechaRegistro),
  };

  factory NoAutorizado.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['fechaRegistro'];
    return NoAutorizado(
      id: id,
      nombre: data['nombre'] as String? ?? '',
      documento: data['documento'] as String? ?? '',
      motivo: data['motivo'] as String? ?? '',
      fkIdRegistradoPor: data['fkIdRegistradoPor'] as String? ?? '',
      nombreRegistradoPor: data['nombreRegistradoPor'] as String? ?? '',
      fechaRegistro: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
    );
  }
}

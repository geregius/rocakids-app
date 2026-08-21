import 'package:cloud_firestore/cloud_firestore.dart';

/// Registro de seguimiento hecho a un niño (típicamente uno que dejó de
/// asistir, ver reporte del Dashboard): qué se hizo/averiguó y qué
/// estado quedó como resultado. A propósito es solo una bitácora — no
/// reemplaza `ninos/{id}.estadoRegistro` (la fuente de verdad de "activo
/// ahora"), sirve para poder evidenciar DESPUÉS que el niño sí se
/// gestionó y por qué quedó en ese estado. Vive en la subcolección
/// `ninos/{ninoId}/gestiones`, visible/editable solo para liderazgo
/// (admin/columna/líder de ministerio) — ver `puedeVerInfoLiderazgo()`
/// en firestore.rules.
class Gestion {
  final String id;
  final String nota;
  final String estadoResultante;
  final String fkIdRegistradoPor;
  final String nombreRegistradoPor;
  final DateTime fecha;

  const Gestion({
    required this.id,
    required this.nota,
    required this.estadoResultante,
    required this.fkIdRegistradoPor,
    required this.nombreRegistradoPor,
    required this.fecha,
  });

  Map<String, dynamic> toFirestore() => {
    'nota': nota,
    'estadoResultante': estadoResultante,
    'fkIdRegistradoPor': fkIdRegistradoPor,
    'nombreRegistradoPor': nombreRegistradoPor,
    'fecha': Timestamp.fromDate(fecha),
  };

  factory Gestion.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['fecha'];
    return Gestion(
      id: id,
      nota: data['nota'] as String? ?? '',
      estadoResultante: data['estadoResultante'] as String? ?? '',
      fkIdRegistradoPor: data['fkIdRegistradoPor'] as String? ?? '',
      nombreRegistradoPor: data['nombreRegistradoPor'] as String? ?? '',
      fecha: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import 'manual_contenido.dart';

final _audienciaPorNombre = {for (final a in AudienciaManual.values) a.name: a};

/// Un video tutorial de YouTube mostrado dentro de "Video Tutoriales"
/// (2026-08-22, pedido de Rafael — misma idea que el manual en PDF, pero
/// en video). Solo se guarda el enlace y unos pocos datos de texto — el
/// video en sí lo sigue sirviendo YouTube, RocaKids nunca lo sube ni lo
/// aloja.
///
/// [titulo] se trae UNA VEZ desde YouTube (oEmbed, ver
/// `utils/youtube_helper.dart`) al crear o editar el video — no se pide
/// escribirlo a mano, para que quede "nombrado como está en YouTube"
/// (pedido explícito de Rafael) sin que se desactualice si alguien
/// cambia el título en YouTube después sin avisar en la app.
class VideoTutorial {
  final String id;
  final String youtubeUrl;
  final String youtubeId;
  final String titulo;
  final String descripcion;
  final List<AudienciaManual> audiencias;
  final DateTime creadoEn;

  const VideoTutorial({
    required this.id,
    required this.youtubeUrl,
    required this.youtubeId,
    required this.titulo,
    this.descripcion = '',
    required this.audiencias,
    required this.creadoEn,
  });

  Map<String, dynamic> toFirestore() => {
    'youtubeUrl': youtubeUrl,
    'youtubeId': youtubeId,
    'titulo': titulo,
    'descripcion': descripcion,
    'audiencias': audiencias.map((a) => a.name).toList(),
  };

  factory VideoTutorial.fromFirestore(String id, Map<String, dynamic> data) {
    final audienciasGuardadas = (data['audiencias'] as List?)?.cast<String>() ?? [];
    final fecha = data['creadoEn'];
    return VideoTutorial(
      id: id,
      youtubeUrl: data['youtubeUrl'] as String? ?? '',
      youtubeId: data['youtubeId'] as String? ?? '',
      titulo: data['titulo'] as String? ?? '',
      descripcion: data['descripcion'] as String? ?? '',
      audiencias: audienciasGuardadas
          .map((s) => _audienciaPorNombre[s])
          .whereType<AudienciaManual>()
          .toList(),
      creadoEn: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
    );
  }
}

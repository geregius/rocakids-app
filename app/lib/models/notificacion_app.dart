import 'package:cloud_firestore/cloud_firestore.dart';

/// Una notificación guardada en `usuarios/{uid}/notificaciones` (2026-09-02,
/// pedido de Rafael) — el historial que se ve al tocar la campana en
/// `AppShell`, además del aviso push real. La escribe siempre una Cloud
/// Function (`enviarNotificacionAUsuarios()`, `functions/index.js`),
/// nunca el cliente.
class NotificacionApp {
  final String id;
  final String titulo;
  final String cuerpo;
  final bool leida;
  final DateTime creadoEn;

  const NotificacionApp({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.leida,
    required this.creadoEn,
  });

  factory NotificacionApp.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['creadoEn'];
    return NotificacionApp(
      id: id,
      titulo: data['titulo'] as String? ?? '',
      cuerpo: data['cuerpo'] as String? ?? '',
      leida: data['leida'] as bool? ?? false,
      creadoEn: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
    );
  }
}

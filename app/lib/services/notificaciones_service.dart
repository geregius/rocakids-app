import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import '../models/notificacion_app.dart';

/// Notificaciones push del navegador/celular vía Firebase Cloud
/// Messaging (2026-09-02, pedido de Rafael: avisar a los servidores de
/// un grupo cuando se les asigna un servicio). Solo funciona si la
/// persona tiene la app instalada/agregada a su pantalla de inicio Y
/// acepta el permiso del navegador cuando se le pide — ninguna de las
/// dos cosas se puede forzar desde el servidor, tienen que pasar
/// dentro de la propia sesión del usuario (ver botón de campana en
/// `widgets/app_shell.dart`).
///
/// **Llave VAPID (pública, no es secreta — mismo criterio que el resto
/// de `firebase_options.dart`, que también va commiteado):** generada
/// una sola vez el 2026-09-02 en Firebase Console → Configuración del
/// proyecto → Cloud Messaging → "Certificados push web". Si se
/// regenera esa llave (o se borra sin querer), hay que actualizar esta
/// constante con la nueva.
const _vapidKeyWeb =
    'BDUdIU951mQPUEvBdRqBHdq0X0HoqUp0KXClwmive2ZtKHV4skBZ69B3SPKi64EPRZ0_kAjsomqK8ou2QvHg_as';

class NotificacionesService {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  NotificacionesService({FirebaseMessaging? messaging, FirebaseFirestore? firestore})
    : _messaging = messaging ?? FirebaseMessaging.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  /// Estado actual del permiso, sin pedirlo — para decidir qué mostrar
  /// en la campana (ya activado / todavía no / rechazado).
  Future<AuthorizationStatus> estadoPermiso() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// Pide el permiso (dispara el diálogo real del navegador — SOLO
  /// funciona si se llama justo después de un toque del usuario, los
  /// navegadores bloquean pedirlo solo). Si lo acepta, guarda el
  /// identificador de ESTE dispositivo en su perfil
  /// (`usuarios/{uid}.fcmTokens`, un array — puede tener varios
  /// dispositivos a la vez). Devuelve `true` si quedó activado.
  Future<bool> activar(String uid) async {
    final settings = await _messaging.requestPermission();
    final autorizado =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!autorizado) return false;

    final token = await _messaging.getToken(vapidKey: _vapidKeyWeb);
    if (token == null) return false;

    await _firestore.collection('usuarios').doc(uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
    return true;
  }

  /// URL de la Cloud Function invocable `enviarNotificacionPrueba`
  /// (región `us-central1` por defecto, igual que
  /// `enviarCorreoRecuperacion` en `AuthService`).
  static const _urlNotificacionPrueba =
      'https://us-central1-rocakidsarmenia-7935b.cloudfunctions.net/enviarNotificacionPrueba';

  /// Manda una notificación de prueba a este mismo usuario (a todos
  /// sus dispositivos activados) — para confirmar de punta a punta que
  /// una vez activadas, las notificaciones sí llegan de verdad.
  ///
  /// Por HTTP directo (protocolo de "función invocable" de Firebase),
  /// no con el paquete `cloud_functions` — ese paquete tiene un bug
  /// conocido y sin resolver en Flutter Web (ver
  /// `AuthService.resetPassword()`, mismo criterio). A diferencia de
  /// `enviarCorreoRecuperacion`, esta función SÍ exige sesión iniciada
  /// — hay que mandar el token de la sesión actual a mano en
  /// `Authorization`, la llamada HTTP directa no lo agrega sola como sí
  /// haría el SDK de `cloud_functions`.
  Future<bool> enviarNotificacionDePrueba() async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null) return false;
    try {
      final respuesta = await http.post(
        Uri.parse(_urlNotificacionPrueba),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'data': {}}),
      );
      if (respuesta.statusCode != 200) return false;
      final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final resultado = cuerpo['result'] as Map<String, dynamic>?;
      return (resultado?['enviados'] as int? ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Historial de notificaciones de este usuario, más reciente primero
  /// (2026-09-02, pedido de Rafael: lista al tocar la campana). Sigue
  /// funcionando aunque este dispositivo nunca haya activado el
  /// permiso push — cada notificación se guarda para TODOS los
  /// destinatarios, no solo para quien tiene un token de dispositivo
  /// (ver `enviarNotificacionAUsuarios()` en `functions/index.js`).
  Stream<List<NotificacionApp>> listarNotificaciones(String uid) {
    return _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('notificaciones')
        .orderBy('creadoEn', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => NotificacionApp.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  /// Marca como leídas todas las notificaciones que todavía no lo
  /// estaban — se llama al abrir la lista desde la campana.
  Future<void> marcarTodasLeidas(String uid, List<NotificacionApp> noLeidas) async {
    if (noLeidas.isEmpty) return;
    final batch = _firestore.batch();
    final ref = _firestore.collection('usuarios').doc(uid).collection('notificaciones');
    for (final n in noLeidas) {
      batch.update(ref.doc(n.id), {'leida': true});
    }
    await batch.commit();
  }

  /// Vuelve a guardar el token si Firebase lo renueva mientras la
  /// persona sigue con la sesión abierta (pasa de vez en cuando, no es
  /// un evento raro) — sin esto, ese dispositivo dejaría de recibir
  /// notificaciones en silencio hasta la próxima vez que tocara
  /// "activar" a mano.
  void escucharRenovacionToken(String uid) {
    _messaging.onTokenRefresh.listen((token) {
      _firestore.collection('usuarios').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
    });
  }
}

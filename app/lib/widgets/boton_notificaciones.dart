import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../services/notificaciones_service.dart';

/// Botón de campana en la barra superior, junto a "Actualizar"
/// (2026-09-02, pedido de Rafael) — activa las notificaciones push de
/// este dispositivo. Campana rellena = ya activadas en este
/// dispositivo; campana vacía = todavía no. Tocarla:
/// - Si nunca se pidió el permiso: lo pide (diálogo real del
///   navegador) y, si lo acepta, guarda el identificador del
///   dispositivo en su perfil.
/// - Si ya está activado: solo confirma que sigue activo.
/// - Si lo había rechazado antes: avisa que hay que habilitarlo a mano
///   desde la configuración del navegador/celular — un sitio web NO
///   puede volver a pedirlo una vez que la persona lo rechazó.
class BotonNotificaciones extends StatefulWidget {
  final String uid;
  const BotonNotificaciones({super.key, required this.uid});

  @override
  State<BotonNotificaciones> createState() => _BotonNotificacionesState();
}

class _BotonNotificacionesState extends State<BotonNotificaciones> {
  final _servicio = NotificacionesService();
  AuthorizationStatus? _estado;

  @override
  void initState() {
    super.initState();
    // Sin `catchError`, un navegador sin soporte real de notificaciones
    // (ver el `try` de `_tocar()`) podría lanzar acá también, apenas se
    // carga la pantalla — no hay nada que mostrar en ese caso, la
    // campana simplemente queda "vacía" (estado por defecto).
    _servicio
        .estadoPermiso()
        .then((e) {
          if (mounted) setState(() => _estado = e);
        })
        .catchError((_) {});
  }

  Future<void> _tocar() async {
    if (_estado == AuthorizationStatus.authorized ||
        _estado == AuthorizationStatus.provisional) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las notificaciones ya están activadas en este dispositivo.')),
      );
      return;
    }
    if (_estado == AuthorizationStatus.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Las notificaciones están bloqueadas para RocaKids. '
            'Actívalas desde la configuración del navegador o del celular.',
          ),
        ),
      );
      return;
    }
    // Este `try` es importante, no decorativo: en un navegador que NO
    // soporta de verdad notificaciones push (ej. Chrome en iPhone —
    // Apple solo permite Service Workers/notificaciones reales dentro
    // de Safari, ver `feature-icono-pantalla-inicio-y-escaner-timeout`)
    // `activar()` puede lanzar una excepción en vez de solo devolver
    // `false` — sin este `try`, eso se veía como "no pasa nada" al
    // tocar la campana (encontrado 2026-09-02, reportado por Rafael en
    // iPhone con Chrome).
    bool activado;
    try {
      activado = await _servicio.activar(widget.uid);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este navegador no admite notificaciones. En iPhone, agrega RocaKids a '
            'la pantalla de inicio usando Safari (no Chrome) y vuelve a intentarlo.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
      return;
    }
    if (!mounted) return;
    final nuevoEstado = await _servicio.estadoPermiso();
    if (!mounted) return;
    setState(() => _estado = nuevoEstado);
    if (!activado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo activar — inténtalo de nuevo.')),
      );
      return;
    }
    // La confirmación real es la notificación de prueba en sí (si
    // llega al dispositivo, quedó bien activado de punta a punta) — el
    // SnackBar es solo un respaldo por si algo falla en el envío.
    final enviada = await _servicio.enviarNotificacionDePrueba();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enviada
              ? '¡Activadas! Te debería llegar una notificación de prueba.'
              : 'Se activaron, pero la notificación de prueba no se pudo enviar.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activo =
        _estado == AuthorizationStatus.authorized || _estado == AuthorizationStatus.provisional;
    return IconButton(
      onPressed: _tocar,
      icon: Icon(activo ? Icons.notifications : Icons.notifications_none),
      tooltip: activo ? 'Notificaciones activadas' : 'Activar notificaciones',
    );
  }
}

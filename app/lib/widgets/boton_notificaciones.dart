import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/notificacion_app.dart';
import '../services/notificaciones_service.dart';
import '../theme/app_colors.dart';

/// Botón de campana en la barra superior, junto a "Actualizar"
/// (2026-09-02, pedido de Rafael) — activa las notificaciones push de
/// este dispositivo y, una vez activadas, muestra el historial al
/// tocarla (más reciente arriba, con contador de no leídas). Campana
/// rellena = ya activadas en este dispositivo; campana vacía = todavía
/// no. Tocarla:
/// - Si nunca se pidió el permiso: lo pide (diálogo real del
///   navegador) y, si lo acepta, guarda el identificador del
///   dispositivo en su perfil.
/// - Si ya está activado: abre la lista de notificaciones
///   (`usuarios/{uid}/notificaciones`, la escribe siempre una Cloud
///   Function — funciona aunque este dispositivo puntual nunca haya
///   activado el permiso, así que el historial en sí no depende de
///   esto, solo el AVISO push).
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

  Future<void> _abrirLista() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ListaNotificacionesSheet(uid: widget.uid, servicio: _servicio),
    );
  }

  Future<void> _tocar() async {
    if (_estado == AuthorizationStatus.authorized ||
        _estado == AuthorizationStatus.provisional) {
      _abrirLista();
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
    // soporta de verdad notificaciones push, `activar()` puede lanzar
    // una excepción en vez de solo devolver `false` — sin este `try`,
    // eso se veía como "no pasa nada" al tocar la campana (encontrado
    // 2026-09-02, reportado por Rafael en iPhone con Chrome). Se
    // muestra el error real (no un mensaje adivinado) porque la MISMA
    // excepción puede tener causas distintas — ej. el primer caso fue
    // Chrome en iOS (nunca soporta esto), pero después volvió a pasar
    // ya instalado con Safari, así que "usa Safari" no era la causa
    // real esa segunda vez — hace falta el texto exacto para saber por
    // qué en cada caso.
    bool activado;
    try {
      activado = await _servicio.activar(widget.uid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo activar: $e'),
          duration: const Duration(seconds: 12),
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
    final icono = IconButton(
      onPressed: _tocar,
      icon: Icon(activo ? Icons.notifications : Icons.notifications_none),
      tooltip: activo ? 'Ver notificaciones' : 'Activar notificaciones',
    );
    if (!activo) return icono;

    // Contador de no leídas (2026-09-02, pedido de Rafael) — solo se
    // pide una vez activadas, para no dejar un listener de Firestore
    // corriendo todo el tiempo en un dispositivo que ni siquiera puede
    // recibir el push.
    return StreamBuilder<List<NotificacionApp>>(
      stream: _servicio.listarNotificaciones(widget.uid),
      builder: (context, snapshot) {
        final noLeidas = (snapshot.data ?? []).where((n) => !n.leida).length;
        return Badge(
          label: Text('$noLeidas'),
          isLabelVisible: noLeidas > 0,
          child: icono,
        );
      },
    );
  }
}

class _ListaNotificacionesSheet extends StatefulWidget {
  final String uid;
  final NotificacionesService servicio;

  const _ListaNotificacionesSheet({required this.uid, required this.servicio});

  @override
  State<_ListaNotificacionesSheet> createState() => _ListaNotificacionesSheetState();
}

class _ListaNotificacionesSheetState extends State<_ListaNotificacionesSheet> {
  bool _yaMarcadas = false;

  String _dos(int n) => n.toString().padLeft(2, '0');

  String _fechaTexto(DateTime f) {
    return '${_dos(f.day)}/${_dos(f.month)}/${f.year} · ${_dos(f.hour)}:${_dos(f.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Notificaciones', style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<NotificacionApp>>(
                stream: widget.servicio.listarNotificaciones(widget.uid),
                builder: (context, snapshot) {
                  final notificaciones = snapshot.data ?? [];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (notificaciones.isEmpty) {
                    return const Center(child: Text('Todavía no tienes notificaciones.'));
                  }
                  // Marcar como leídas apenas se ven, no antes de saber
                  // qué hay (evita marcar "leído" algo que en realidad
                  // nunca llegó a mostrarse, ej. si la lista falla).
                  final noLeidas = notificaciones.where((n) => !n.leida).toList();
                  if (!_yaMarcadas && noLeidas.isNotEmpty) {
                    _yaMarcadas = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.servicio.marcarTodasLeidas(widget.uid, noLeidas);
                    });
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notificaciones.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = notificaciones[i];
                      return ListTile(
                        leading: Icon(
                          Icons.notifications,
                          color: n.leida ? Colors.grey : AppColors.azulMarino,
                        ),
                        title: Text(
                          n.titulo,
                          style: TextStyle(fontWeight: n.leida ? FontWeight.normal : FontWeight.bold),
                        ),
                        subtitle: Text('${n.cuerpo}\n${_fechaTexto(n.creadoEn)}'),
                        isThreeLine: true,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

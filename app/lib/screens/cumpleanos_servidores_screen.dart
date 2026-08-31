import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'admin/user_edit_sheet.dart';

/// Sección "Cumpleaños Servidores" (2026-08-19, pedido de Rafael;
/// reordenada 2026-08-29) — a diferencia de la versión de niños,
/// **solo administrador, columna y líder de ministerio** la ven
/// (`RolUsuario.puedeVerAcudientesYNinos`) — `usuarios` guarda datos
/// sensibles del servidor (documento, teléfono, EPS) ya acotados a
/// liderazgo en el resto de la app (Dashboard, Acudientes y Niños), así
/// que esta sección sigue el mismo criterio en vez del más abierto de
/// "Cumpleaños niños".
///
/// **2026-08-29:** ya no muestra solo "quién cumplió en la última
/// semana" — ahora trae a TODOS los servidores activos
/// (`AuthService.obtenerTodosLosServidoresActivos`, colección chica,
/// ~30 servidores, traerla completa es barato) y los ordena de quién
/// cumple más pronto a quién más falta (`diasHastaProximoCumpleanos`),
/// para poder ver de un vistazo quién está próximo. Los que todavía no
/// tienen fecha de nacimiento registrada quedan aparte, al final.
///
/// La fecha de nacimiento del servidor es un dato NUEVO — no existía en
/// el sistema anterior, así que empieza vacía para todos los ya
/// migrados hasta que cada quien la llene desde "Mi perfil" → "Editar
/// información" (o un admin se la complete).
class CumpleanosServidoresScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const CumpleanosServidoresScreen({super.key, required this.usuario});

  @override
  State<CumpleanosServidoresScreen> createState() =>
      _CumpleanosServidoresScreenState();
}

class _CumpleanosServidoresScreenState
    extends State<CumpleanosServidoresScreen> {
  final _authService = AuthService();
  late Future<List<UsuarioApp>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _authService.obtenerTodosLosServidoresActivos();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Cumpleaños Servidores',
      body: (context) => FutureBuilder<List<UsuarioApp>>(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final todos = [...?snapshot.data];
          if (todos.isEmpty) {
            return const Center(child: Text('No hay servidores activos.'));
          }

          final conFecha = todos.where((s) => s.fechaNacimiento != null).toList()
            ..sort((a, b) {
              final diasA = diasHastaProximoCumpleanos(a.fechaNacimiento!);
              final diasB = diasHastaProximoCumpleanos(b.fechaNacimiento!);
              final porDia = diasA.compareTo(diasB);
              return porDia != 0
                  ? porDia
                  : a.nombreCompleto.toLowerCase().compareTo(
                      b.nombreCompleto.toLowerCase(),
                    );
            });
          final sinFecha = todos.where((s) => s.fechaNacimiento == null).toList()
            ..sort(
              (a, b) => a.nombreCompleto.toLowerCase().compareTo(
                b.nombreCompleto.toLowerCase(),
              ),
            );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...conFecha.map(
                (s) => _CumpleanosServidorTile(
                  servidor: s,
                  esAdmin: widget.usuario.rol == RolUsuario.administrador,
                ),
              ),
              if (sinFecha.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'Sin fecha de nacimiento registrada',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.azulMarino.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                ...sinFecha.map(
                  (s) => _CumpleanosServidorTile(
                    servidor: s,
                    esAdmin: widget.usuario.rol == RolUsuario.administrador,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CumpleanosServidorTile extends StatelessWidget {
  final UsuarioApp servidor;
  final bool esAdmin;

  const _CumpleanosServidorTile({
    required this.servidor,
    required this.esAdmin,
  });

  String _etiquetaFecha() {
    final fecha = servidor.fechaNacimiento;
    if (fecha == null) return 'Sin fecha registrada';
    final dias = diasHastaProximoCumpleanos(fecha);
    if (dias == 0) return 'Cumple hoy';
    if (dias == 1) return 'Cumple mañana';
    return 'Cumple en $dias días';
  }

  @override
  Widget build(BuildContext context) {
    final fecha = servidor.fechaNacimiento;
    final hoy = fecha != null && diasHastaProximoCumpleanos(fecha) == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => UserEditSheet(usuario: servidor, esAdmin: esAdmin),
        ),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.amarillo,
          backgroundImage: servidor.fotoUrl.isNotEmpty
              ? NetworkImage(servidor.fotoUrl)
              : null,
          child: servidor.fotoUrl.isEmpty
              ? Text(servidor.nombre.isNotEmpty ? servidor.nombre[0] : '?')
              : null,
        ),
        title: Text(servidor.nombreCompleto),
        subtitle: Text(servidor.rol.etiqueta),
        trailing: Chip(
          avatar: Icon(
            Icons.cake,
            size: 18,
            color: hoy ? Colors.white : AppColors.azulMarino,
          ),
          label: Text(_etiquetaFecha()),
          labelStyle: TextStyle(
            color: hoy ? Colors.white : AppColors.azulMarino,
          ),
          backgroundColor: hoy
              ? AppColors.rojo
              : AppColors.amarillo.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

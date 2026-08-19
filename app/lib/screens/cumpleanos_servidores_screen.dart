import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'admin/user_edit_sheet.dart';

/// Sección "Cumpleaños Servidores" (2026-08-19, pedido de Rafael) —
/// misma mecánica que "Cumpleaños niños" pero sobre `usuarios`: quiénes
/// cumplen años hoy o cumplieron en los últimos 7 días
/// (`AuthService.obtenerServidoresQueCumplieronEstaSemana`). A
/// diferencia de la versión de niños, **solo administrador, columna y
/// líder de ministerio** la ven (`RolUsuario.puedeVerAcudientesYNinos`)
/// — `usuarios` guarda datos sensibles del servidor (documento,
/// teléfono, EPS) ya acotados a liderazgo en el resto de la app
/// (Dashboard, Acudientes y Niños), así que esta sección sigue el mismo
/// criterio en vez del más abierto de "Cumpleaños niños".
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
    _futuro = _authService.obtenerServidoresQueCumplieronEstaSemana();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Cumpleaños Servidores',
      body: FutureBuilder<List<UsuarioApp>>(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final servidores = [...?snapshot.data]
            ..sort((a, b) {
              final diasA = diasDesdeCumpleanos(a.fechaNacimiento!) ?? 99;
              final diasB = diasDesdeCumpleanos(b.fechaNacimiento!) ?? 99;
              final porDia = diasA.compareTo(diasB);
              return porDia != 0
                  ? porDia
                  : a.nombreCompleto.toLowerCase().compareTo(
                      b.nombreCompleto.toLowerCase(),
                    );
            });

          if (servidores.isEmpty) {
            return const Center(
              child: Text(
                'Ningún servidor ha cumplido años en la última semana.',
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: servidores.length,
            itemBuilder: (context, i) => _CumpleanosServidorTile(
              servidor: servidores[i],
              esAdmin: widget.usuario.rol == RolUsuario.administrador,
            ),
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
    final dias = diasDesdeCumpleanos(servidor.fechaNacimiento!);
    if (dias == null) return '';
    if (dias == 0) return 'Cumple hoy';
    if (dias == 1) return 'Cumplió ayer';
    return 'Cumplió hace $dias días';
  }

  @override
  Widget build(BuildContext context) {
    final hoy = diasDesdeCumpleanos(servidor.fechaNacimiento!) == 0;

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

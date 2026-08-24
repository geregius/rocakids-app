import 'package:flutter/material.dart';

import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';
import 'user_edit_sheet.dart';

class AdminUsersListScreen extends StatelessWidget {
  final UsuarioApp usuario;

  const AdminUsersListScreen({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    // Quien abre esta pantalla ya tiene `puedeGestionarServidores` (se
    // exige en el menú de `AppShell`), así que acá siempre es true — se
    // recalcula igual, en vez de asumirlo, para no depender de ese
    // único punto de entrada.
    final puedeGestionar = usuario.rol.puedeGestionarServidores;

    return AppShell(
      usuario: usuario,
      seccionActiva: 'Gestión de Servidores',
      body: StreamBuilder<List<UsuarioApp>>(
        stream: authService.listarUsuarios(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          // Los acudientes (rol usuario_externo) tienen su propia pantalla
          // ("Acudientes y Niños") — aquí solo van los roles de servidor.
          final usuarios = (snapshot.data ?? [])
              .where((u) => u.rol != RolUsuario.usuarioExterno)
              .toList();
          if (usuarios.isEmpty) {
            return const Center(child: Text('Todavía no hay usuarios registrados.'));
          }

          final pendientes = usuarios.where((u) => u.rol == RolUsuario.pendiente).toList();
          final resto = usuarios.where((u) => u.rol != RolUsuario.pendiente).toList();

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (pendientes.isNotEmpty) ...[
                _Seccion(titulo: 'Pendientes de aprobación (${pendientes.length})'),
                ...pendientes.map((u) => _UsuarioTile(usuario: u, puedeGestionar: puedeGestionar)),
                const Divider(height: 24),
              ],
              _Seccion(titulo: 'Todos los usuarios (${resto.length})'),
              ...resto.map((u) => _UsuarioTile(usuario: u, puedeGestionar: puedeGestionar)),
            ],
          );
        },
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  const _Seccion({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        titulo,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey.shade600),
      ),
    );
  }
}

class _UsuarioTile extends StatelessWidget {
  final UsuarioApp usuario;
  final bool puedeGestionar;
  const _UsuarioTile({required this.usuario, required this.puedeGestionar});

  @override
  Widget build(BuildContext context) {
    final esPendiente = usuario.rol == RolUsuario.pendiente;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: esPendiente ? AppColors.amarillo : AppColors.azulMarino,
        foregroundColor: esPendiente ? AppColors.textoPrincipal : Colors.white,
        backgroundImage: usuario.fotoUrl.isNotEmpty ? NetworkImage(usuario.fotoUrl) : null,
        child: usuario.fotoUrl.isEmpty
            ? Text(usuario.nombre.isNotEmpty ? usuario.nombre[0].toUpperCase() : '?')
            : null,
      ),
      title: Text(usuario.nombreCompleto.isNotEmpty ? usuario.nombreCompleto : usuario.correo),
      subtitle: Text('${usuario.correo} · ${usuario.rol.etiqueta}'),
      trailing: !usuario.activo
          ? const Icon(Icons.block, color: AppColors.rojo)
          : (esPendiente ? const Icon(Icons.priority_high, color: AppColors.rojo) : null),
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => UserEditSheet(usuario: usuario, esAdmin: puedeGestionar),
        );
      },
    );
  }
}

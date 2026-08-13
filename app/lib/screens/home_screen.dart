import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import 'admin/admin_users_list_screen.dart';
import 'admin/user_edit_sheet.dart';

class HomeScreen extends StatelessWidget {
  final UsuarioApp usuario;

  const HomeScreen({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RocaKids'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Bienvenido, ${usuario.nombre.isNotEmpty ? usuario.nombre : usuario.correo}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('Rol: ${usuario.rol.etiqueta}'),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              icon: const Icon(Icons.person),
              label: const Text('Mi perfil'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => UserEditSheet(usuario: usuario, esAdmin: true),
              ),
            ),
            const SizedBox(height: 12),
            if (usuario.rol == RolUsuario.administrador)
              ElevatedButton.icon(
                icon: const Icon(Icons.people),
                label: const Text('Gestión de Servidores'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminUsersListScreen()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

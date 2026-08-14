import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import 'acudiente_portal_screen.dart';
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
            icon: const Icon(Icons.person),
            tooltip: 'Mi perfil',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => UserEditSheet(usuario: usuario, esAdmin: true),
            ),
          ),
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
              icon: const Icon(Icons.family_restroom),
              label: const Text('Mis hijos'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AcudientePortalScreen(usuario: usuario)),
              ),
            ),
            const SizedBox(height: 12),
            if (usuario.rol == RolUsuario.administrador) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.people),
                label: const Text('Gestión de Servidores'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminUsersListScreen()),
                ),
              ),
              const SizedBox(height: 20),
              const _BotonReindexarBusqueda(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Herramienta de mantenimiento (solo admin): rellena `ninos_busqueda`
/// para niños que quedaron sin su copia de búsqueda — ej. los
/// registrados antes de que existiera esa colección, o si un futuro
/// script de importación masiva (Módulo 2) se olvida de escribirla.
class _BotonReindexarBusqueda extends StatefulWidget {
  const _BotonReindexarBusqueda();

  @override
  State<_BotonReindexarBusqueda> createState() => _BotonReindexarBusquedaState();
}

class _BotonReindexarBusquedaState extends State<_BotonReindexarBusqueda> {
  bool _cargando = false;

  Future<void> _reindexar() async {
    setState(() => _cargando = true);
    try {
      final total = await AuthService().reindexarBusquedaNinos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$total niños reindexados para la búsqueda por nombre.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo reindexar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _cargando ? null : _reindexar,
      icon: _cargando
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync, size: 18),
      label: const Text('Reindexar búsqueda de niños'),
    );
  }
}

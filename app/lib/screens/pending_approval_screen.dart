import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';

/// Pantalla que ve cualquier usuario cuyo rol todavía no le da acceso
/// a ningún módulo (usuario_externo recién registrado, o rol
/// desconocido/legacy).
class PendingApprovalScreen extends StatelessWidget {
  final UsuarioApp usuario;

  const PendingApprovalScreen({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Hola, ${usuario.nombre.isNotEmpty ? usuario.nombre : usuario.correo}',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tu cuenta fue creada correctamente. Un administrador debe '
                  'asignarte un rol antes de que puedas continuar.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => AuthService().signOut(),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

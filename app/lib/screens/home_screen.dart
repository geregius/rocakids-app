import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';

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
            Text('Rol: ${usuario.rol.name}'),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../widgets/app_shell.dart';

class HomeScreen extends StatelessWidget {
  final UsuarioApp usuario;

  const HomeScreen({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: usuario,
      seccionActiva: 'Inicio',
      construirPantalla: () => HomeScreen(usuario: usuario),
      body: (context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Bienvenido, ${usuario.nombre.isNotEmpty ? usuario.nombre : usuario.correo}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('Rol: ${usuario.rol.etiqueta}'),
          ],
        ),
      ),
    );
  }
}

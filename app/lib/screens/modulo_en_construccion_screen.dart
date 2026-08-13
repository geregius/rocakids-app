import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import 'admin/user_edit_sheet.dart';

/// Para roles ya aprobados y con perfil completo, pero cuyas pantallas
/// propias todavía no existen (se activan módulo por módulo).
class ModuloEnConstruccionScreen extends StatelessWidget {
  final UsuarioApp usuario;

  const ModuloEnConstruccionScreen({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Image.asset('assets/images/logo_rocakids_compacto.png', height: 40, fit: BoxFit.contain),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Mi perfil',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => UserEditSheet(usuario: usuario, esAdmin: false),
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction, size: 56),
              const SizedBox(height: 16),
              Text(
                'Hola, ${usuario.nombre}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('Tu rol: ${usuario.rol.etiqueta}'),
              const SizedBox(height: 16),
              const Text(
                'Tu perfil está completo. Las herramientas para tu rol se '
                'están construyendo y estarán disponibles pronto.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

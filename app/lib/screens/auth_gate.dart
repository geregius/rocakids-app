import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import 'complete_profile_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'modulo_en_construccion_screen.dart';
import 'pending_approval_screen.dart';

/// Decide qué pantalla mostrar según el estado de autenticación y el
/// perfil del usuario. Reacciona en tiempo real: si un admin aprueba a
/// alguien, o si el usuario completa su perfil, la pantalla cambia sola
/// sin necesitar cerrar sesión ni refrescar.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        return StreamBuilder<UsuarioApp>(
          stream: authService.usuarioActualStream(),
          builder: (context, usuarioSnapshot) {
            if (usuarioSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (usuarioSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${usuarioSnapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => authService.signOut(),
                          child: const Text('Cerrar sesión'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final usuario = usuarioSnapshot.data!;

            if (!usuario.rol.esRolDeServidor) {
              // pendiente / usuario_externo / desconocido: todavía no
              // tienen módulos propios en la app.
              return PendingApprovalScreen(usuario: usuario);
            }

            if (!usuario.perfilCompleto) {
              // Bloqueo obligatorio: no puede hacer nada más hasta
              // completar todos los datos de su perfil de servidor.
              return CompleteProfileScreen(usuario: usuario);
            }

            if (usuario.rol == RolUsuario.administrador) {
              return HomeScreen(usuario: usuario);
            }

            return ModuloEnConstruccionScreen(usuario: usuario);
          },
        );
      },
    );
  }
}

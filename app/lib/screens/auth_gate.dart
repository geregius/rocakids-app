import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Decide qué pantalla mostrar según el estado de autenticación:
/// sin sesión -> Login; con sesión -> busca su rol y muestra Home.
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

        return FutureBuilder<UsuarioApp>(
          future: authService.obtenerUsuarioActual(),
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

            return HomeScreen(usuario: usuarioSnapshot.data!);
          },
        );
      },
    );
  }
}

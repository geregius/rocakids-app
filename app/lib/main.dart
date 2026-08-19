import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/reset_password_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const RocaKidsApp());
}

class RocaKidsApp extends StatelessWidget {
  const RocaKidsApp({super.key});

  /// El correo de recuperación de contraseña (`enviarCorreoRecuperacion`
  /// en functions/index.js, `handleCodeInApp: true`) abre la app
  /// directamente con `?mode=resetPassword&oobCode=...` en la URL, en
  /// vez de la página genérica de Firebase — así se detecta acá para
  /// mostrar la pantalla propia en vez del login normal.
  Widget _pantallaInicial() {
    final params = Uri.base.queryParameters;
    if (params['mode'] == 'resetPassword' && (params['oobCode']?.isNotEmpty ?? false)) {
      return ResetPasswordScreen(oobCode: params['oobCode']!);
    }
    return const AuthGate();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RocaKids',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _pantallaInicial(),
    );
  }
}

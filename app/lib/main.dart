import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/reset_password_screen.dart';
import 'theme/app_theme.dart';

/// Firebase App Check (2026-08-21, hallazgo de la auditoría de
/// seguridad: "sin protección contra bots") — la clave del SITIO de
/// reCAPTCHA v3 para Web (generada por Rafael en google.com/recaptcha/admin
/// el mismo día; la CLAVE SECRETA correspondiente se guardó aparte en
/// Firebase Console → App Check, nunca en este repo). NO es un secreto
/// (se usa en el cliente, igual que el `apiKey` de Firebase en
/// `firebase_options.dart`): la protección real la da que Firebase
/// verifique el token contra la clave secreta en su propio backend, no
/// que esta clave de sitio esté oculta.
const _reCaptchaV3SiteKeyWeb = '6LdjapItAAAAAOEA-WJ28cYLOMdBJ-shmjtKlUdl';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // A propósito SIN `await` y con su propio try/catch: activar App Check
  // implica que el navegador cargue el script de reCAPTCHA y consiga un
  // token, algo que puede tardar o fallar (red lenta, clave todavía sin
  // reemplazar, servicio de Google caído) — la app nunca debe quedar
  // colgada en la pantalla de carga por esto. Mientras no haya un token
  // válido, las peticiones simplemente no lo llevan; no pasa nada hasta
  // que se active el modo "Enforce" en la consola de Firebase.
  unawaited(
    FirebaseAppCheck.instance
        .activate(
          providerWeb: ReCaptchaV3Provider(_reCaptchaV3SiteKeyWeb),
          providerAndroid: AndroidDebugProvider(),
          providerApple: AppleDebugProvider(),
        )
        .catchError((_) {}),
  );
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/usuario_app.dart';

class AuthException implements Exception {
  final String mensaje;
  const AuthException(this.mensaje);
}

/// Punto único de acceso a Firebase Auth + al documento de rol en Firestore.
/// El rol nunca lo decide el cliente: se lee de `usuarios/{uid}` después
/// de un login exitoso.
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signIn({required String correo, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: correo.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mensajeDeError(e.code));
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Busca el perfil/rol del usuario logueado en Firestore.
  /// Si no existe el documento, el usuario está autenticado pero
  /// no tiene acceso a ningún módulo todavía (rol desconocido).
  Future<UsuarioApp> obtenerUsuarioActual() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }

    final doc = await _firestore.collection('usuarios').doc(user.uid).get();
    if (!doc.exists) {
      throw const AuthException(
        'Tu cuenta no tiene un perfil asignado en el sistema. Contacta a un administrador.',
      );
    }

    return UsuarioApp.fromFirestore(user.uid, doc.data()!);
  }

  String _mensajeDeError(String codigo) {
    switch (codigo) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      case 'invalid-email':
        return 'El correo ingresado no es válido.';
      case 'user-disabled':
        return 'Esta cuenta está deshabilitada.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta de nuevo en unos minutos.';
      default:
        return 'No se pudo iniciar sesión. Intenta de nuevo.';
    }
  }
}

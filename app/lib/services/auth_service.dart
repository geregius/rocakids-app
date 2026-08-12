import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/usuario_app.dart';

class AuthException implements Exception {
  final String mensaje;
  const AuthException(this.mensaje);
}

/// Punto único de acceso a Firebase Auth + al documento de rol en Firestore.
/// El rol nunca lo decide el cliente: se lee de `usuarios/{uid}` después
/// de un login exitoso, y solo un administrador puede cambiarlo
/// (reglas de seguridad en firestore.rules).
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signIn({required String correo, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: correo.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mensajeDeError(e.code));
    }
  }

  /// Auto-registro de un SERVIDOR (voluntario/líder). Queda con rol
  /// "pendiente" — fijado también por las reglas de seguridad, así que
  /// aunque alguien manipule la app no puede autoasignarse un rol con
  /// más permisos. Un administrador debe revisar y asignarle su rol
  /// real desde "Gestión de Servidores".
  Future<void> signUpServidor({
    required String correo,
    required String password,
    required String nombre,
    required String apellido,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: correo.trim(),
        password: password,
      );
      final uid = credential.user!.uid;
      await _firestore.collection('usuarios').doc(uid).set({
        'correo': correo.trim(),
        'nombre': nombre.trim(),
        'apellido': apellido.trim(),
        'rol': RolUsuario.pendiente.valorFirestore,
        'activo': true,
        'creadoEn': FieldValue.serverTimestamp(),
      });
      // Cerramos la sesión de inmediato: la cuenta queda pendiente y no
      // hay nada que hacer estando "logueado" en ese estado. Así el
      // mensaje de confirmación queda bajo nuestro control (no depende
      // de una pantalla que aparece sola por el cambio de auth state).
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mensajeDeErrorRegistro(e.code));
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Stream reactivo del perfil del usuario logueado: se actualiza solo
  /// cuando un admin le asigna rol, o cuando el propio usuario completa
  /// su perfil — sin necesitar refrescos manuales de pantalla.
  Stream<UsuarioApp> usuarioActualStream() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    return _firestore.collection('usuarios').doc(user.uid).snapshots().map((doc) {
      if (!doc.exists) {
        throw const AuthException(
          'Tu cuenta no tiene un perfil asignado en el sistema. Contacta a un administrador.',
        );
      }
      return UsuarioApp.fromFirestore(user.uid, doc.data()!);
    });
  }

  /// Solo funciona si quien llama es admin (lo garantizan las reglas
  /// de seguridad; si no lo es, Firestore rechaza la consulta).
  Stream<List<UsuarioApp>> listarUsuarios() {
    return _firestore.collection('usuarios').snapshots().map(
      (snap) => snap.docs.map((d) => UsuarioApp.fromFirestore(d.id, d.data())).toList()
        ..sort((a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase())),
    );
  }

  Future<void> actualizarRolYEstado({
    required String uid,
    required RolUsuario rol,
    required bool activo,
    DateTime? fechaVerificacionAntecedentes,
  }) {
    return _firestore.collection('usuarios').doc(uid).update({
      'rol': rol.valorFirestore,
      'activo': activo,
      if (fechaVerificacionAntecedentes != null)
        'fechaVerificacionAntecedentes': Timestamp.fromDate(fechaVerificacionAntecedentes),
    });
  }

  /// El propio servidor completa su perfil (documento, EPS, contacto de
  /// emergencia, foto). Las reglas de seguridad le impiden tocar su rol
  /// o su estado activo desde aquí.
  Future<void> completarPerfilServidor({
    required String tipoDocumento,
    required String numeroDocumento,
    required String telefono,
    required String epsNombre,
    required String grupoSanguineo,
    required String contactoEmergenciaNombre,
    required String contactoEmergenciaTelefono,
    required String fotoUrl,
  }) {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    return _firestore.collection('usuarios').doc(user.uid).update({
      'tipoDocumento': tipoDocumento,
      'numeroDocumento': numeroDocumento,
      'telefono': telefono,
      'epsNombre': epsNombre,
      'grupoSanguineo': grupoSanguineo,
      'contactoEmergenciaNombre': contactoEmergenciaNombre,
      'contactoEmergenciaTelefono': contactoEmergenciaTelefono,
      'fotoUrl': fotoUrl,
    });
  }

  /// Sube la foto de perfil del servidor logueado y devuelve la URL
  /// pública para guardarla en su documento.
  Future<String> subirFotoServidor(Uint8List bytes, String extension) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final ref = _storage.ref('servidores_fotos/${user.uid}/foto.$extension');
    await ref.putData(bytes);
    return ref.getDownloadURL();
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

  String _mensajeDeErrorRegistro(String codigo) {
    switch (codigo) {
      case 'email-already-in-use':
        return 'Ya existe una cuenta con este correo.';
      case 'invalid-email':
        return 'El correo ingresado no es válido.';
      case 'weak-password':
        return 'La contraseña es muy débil (mínimo 6 caracteres).';
      default:
        return 'No se pudo crear la cuenta. Intenta de nuevo.';
    }
  }
}

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
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

  /// Auto-registro de un ACUDIENTE junto con su primer niño y la relación
  /// entre ambos. A diferencia del servidor, el acudiente obtiene acceso
  /// inmediato (rol "usuario_externo", sin aprobación de un admin).
  ///
  /// Los tres documentos se crean en un solo batch atómico. El ID del
  /// niño es su "llave interna" (documento, o fecha+nombre+apellido si
  /// no tiene) — así las reglas de seguridad rechazan automáticamente
  /// un documento duplicado (ver firestore.rules).
  Future<void> registrarAcudienteConNino({
    required String correo,
    required String password,
    required Acudiente acudiente,
    required Nino nino,
    required String parentescoTipo,
  }) async {
    UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: correo.trim(),
        password: password,
      );
      final uid = credential.user!.uid;

      final batch = _firestore.batch();
      batch.set(_firestore.collection('usuarios').doc(uid), {
        'correo': correo.trim(),
        'nombre': acudiente.nombres,
        'apellido': acudiente.apellidos,
        'rol': RolUsuario.usuarioExterno.valorFirestore,
        'activo': true,
        'creadoEn': FieldValue.serverTimestamp(),
      });
      batch.set(_firestore.collection('acudientes').doc(uid), acudiente.toFirestore());
      batch.set(
        _firestore.collection('acudientes_documentos').doc(acudiente.numeroDocumento),
        {'uid': uid},
      );
      batch.set(
        _firestore.collection('ninos').doc(nino.documentoIdentificacion),
        nino.toFirestore(),
      );
      batch.set(
        _firestore.collection('nino_acudiente').doc(),
        NinoAcudiente(
          id: '',
          fkIdNino: nino.documentoIdentificacion,
          fkIdAcudiente: uid,
          parentescoTipo: parentescoTipo,
          autorizacionFormulario: 'Sí',
          autorizacionImagen: nino.autorizoFotoFlag ? 'Sí' : 'No',
          esRepresentanteLegalFlag: true,
        ).toFirestore(),
      );
      await batch.commit();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mensajeDeErrorRegistro(e.code));
    } catch (e) {
      // Si el batch falla (ej. documento del niño duplicado), no dejamos
      // una cuenta de acceso huérfana sin perfil: la eliminamos para que
      // la persona pueda corregir el dato e intentar de nuevo.
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {
          await _auth.signOut();
        }
      }
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'Este número de documento ya se encuentra registrado en el sistema.',
        );
      }
      throw AuthException('No se pudo completar el registro: $e');
    }
  }

  /// Los niños vinculados al acudiente logueado.
  Future<List<Nino>> obtenerMisHijos() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final relaciones = await _firestore
        .collection('nino_acudiente')
        .where('fk_idAcudiente', isEqualTo: user.uid)
        .get();

    final ninos = <Nino>[];
    for (final rel in relaciones.docs) {
      final ninoId = rel.data()['fk_idNino'] as String?;
      if (ninoId == null) continue;
      final ninoDoc = await _firestore.collection('ninos').doc(ninoId).get();
      if (ninoDoc.exists) {
        ninos.add(Nino.fromFirestore(ninoDoc.id, ninoDoc.data()!));
      }
    }
    return ninos;
  }

  /// Busca un niño ya registrado por su documento (o llave interna) y,
  /// si existe, lo vincula al acudiente logueado. Vínculo inmediato, sin
  /// aprobación — el control real de quién retira a un niño ocurre en
  /// el check-in/check-out, no aquí.
  Future<Nino> vincularNinoExistente({
    required String documentoNino,
    required String parentescoTipo,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }

    final docId = documentoNino.trim().toUpperCase();
    final ninoDoc = await _firestore.collection('ninos').doc(docId).get();
    if (!ninoDoc.exists) {
      throw const AuthException('No se encontró ningún niño con ese documento.');
    }
    final nino = Nino.fromFirestore(ninoDoc.id, ninoDoc.data()!);

    // Evita crear una relación duplicada si ya estaban vinculados.
    final yaVinculado = await _firestore
        .collection('nino_acudiente')
        .where('fk_idAcudiente', isEqualTo: user.uid)
        .where('fk_idNino', isEqualTo: docId)
        .limit(1)
        .get();
    if (yaVinculado.docs.isNotEmpty) {
      throw const AuthException('Ya estás vinculado a este niño.');
    }

    await _firestore.collection('nino_acudiente').add(
      NinoAcudiente(
        id: '',
        fkIdNino: docId,
        fkIdAcudiente: user.uid,
        parentescoTipo: parentescoTipo,
        autorizacionFormulario: 'Sí',
        autorizacionImagen: nino.autorizoFotoFlag ? 'Sí' : 'No',
        esRepresentanteLegalFlag: false,
      ).toFirestore(),
    );
    return nino;
  }

  /// Registra un niño NUEVO y lo vincula al acudiente logueado (para
  /// cuando ya tiene cuenta y quiere agregar otro hijo).
  Future<void> registrarNinoAdicional({
    required Nino nino,
    required String parentescoTipo,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }

    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('ninos').doc(nino.documentoIdentificacion),
      nino.toFirestore(),
    );
    batch.set(
      _firestore.collection('nino_acudiente').doc(),
      NinoAcudiente(
        id: '',
        fkIdNino: nino.documentoIdentificacion,
        fkIdAcudiente: user.uid,
        parentescoTipo: parentescoTipo,
        autorizacionFormulario: 'Sí',
        autorizacionImagen: nino.autorizoFotoFlag ? 'Sí' : 'No',
        esRepresentanteLegalFlag: true,
      ).toFirestore(),
    );

    try {
      await batch.commit();
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'Este número de documento ya se encuentra registrado en el sistema.',
        );
      }
      throw AuthException('No se pudo registrar al niño: $e');
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

  /// Completa/edita el perfil de un servidor (documento, EPS, contacto de
  /// emergencia, foto). Sirve tanto para que el propio servidor llene su
  /// perfil por primera vez, como para que un admin corrija los datos de
  /// otro — en ambos casos las reglas de seguridad impiden tocar el rol
  /// o el estado activo por esta vía (eso es siempre responsabilidad del
  /// admin, con [actualizarRolYEstado]).
  Future<void> completarPerfilServidor({
    String? uid,
    required String tipoDocumento,
    required String numeroDocumento,
    required String telefono,
    required String epsNombre,
    required String grupoSanguineo,
    required String contactoEmergenciaNombre,
    required String contactoEmergenciaTelefono,
    required String fotoUrl,
  }) {
    final destinoUid = uid ?? _auth.currentUser?.uid;
    if (destinoUid == null) {
      throw const AuthException('No hay sesión activa.');
    }
    return _firestore.collection('usuarios').doc(destinoUid).update({
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
  /// pública para guardarla en su documento. Las reglas de Storage solo
  /// permiten que cada quien suba su propia foto (un admin no puede
  /// reemplazar la foto de otro servidor).
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

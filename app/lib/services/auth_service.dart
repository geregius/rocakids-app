import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
import '../models/registro.dart';
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

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signIn({
    required String correo,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: correo.trim(),
        password: password,
      );
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
    Uint8List? fotoAcudienteBytes,
    String? fotoAcudienteExt,
    Uint8List? fotoNinoBytes,
    String? fotoNinoExt,
  }) async {
    UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: correo.trim(),
        password: password,
      );
      final uid = credential.user!.uid;

      // Las fotos se suben aquí (no antes) porque hasta ahora no existía
      // sesión con la que Storage pudiera autorizar la subida.
      String fotoAcudienteUrl = '';
      if (fotoAcudienteBytes != null && fotoAcudienteExt != null) {
        fotoAcudienteUrl = await subirFotoAcudiente(
          fotoAcudienteBytes,
          fotoAcudienteExt,
        );
      }
      String fotoNinoUrl = '';
      if (fotoNinoBytes != null && fotoNinoExt != null) {
        fotoNinoUrl = await subirFotoNino(
          nino.documentoIdentificacion,
          fotoNinoBytes,
          fotoNinoExt,
        );
      }

      final batch = _firestore.batch();
      batch.set(_firestore.collection('usuarios').doc(uid), {
        'correo': correo.trim(),
        'nombre': acudiente.nombres,
        'apellido': acudiente.apellidos,
        'rol': RolUsuario.usuarioExterno.valorFirestore,
        'activo': true,
        'creadoEn': FieldValue.serverTimestamp(),
      });
      batch.set(_firestore.collection('acudientes').doc(uid), {
        ...acudiente.toFirestore(),
        if (fotoAcudienteUrl.isNotEmpty) 'fotoSeguridadUrl': fotoAcudienteUrl,
      });
      batch.set(
        _firestore
            .collection('acudientes_documentos')
            .doc(acudiente.numeroDocumento),
        {'uid': uid},
      );
      batch.set(
        _firestore.collection('ninos').doc(nino.documentoIdentificacion),
        {
          ...nino.toFirestore(),
          if (fotoNinoUrl.isNotEmpty) 'fotoUrl': fotoNinoUrl,
        },
      );
      batch.set(
        _firestore
            .collection('ninos_busqueda')
            .doc(nino.documentoIdentificacion),
        NinoBusqueda(
          documentoIdentificacion: nino.documentoIdentificacion,
          nombres: nino.nombres,
          apellidos: nino.apellidos,
          fechaNacimiento: nino.fechaNacimiento,
        ).toFirestore(),
      );
      batch.set(
        _firestore
            .collection('nino_acudiente')
            .doc('${nino.documentoIdentificacion}_$uid'),
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
      if (e.code == 'email-already-in-use') {
        throw const AuthException(
          'Ya tienes una cuenta con este correo. Inicia sesión y usa '
          '"Mis hijos" desde tu pantalla principal para registrar niños '
          '— no hace falta crear una cuenta nueva.',
        );
      }
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

  /// Lo mismo que [registrarAcudienteConNino], pero hecho por un
  /// SERVIDOR (cualquier rol operativo, ver AppShell) en nombre de una
  /// familia — ej. en la mesa de registro de un servicio, cuando el papá o la mamá
  /// no puede hacerlo desde su propio celular.
  ///
  /// La diferencia clave: quien llama YA tiene su propia sesión abierta
  /// (el maestro) y no se puede perder. Crear la cuenta nueva con la app
  /// de Firebase "de siempre" dejaría al maestro logueado como la
  /// familia nueva en vez de como él mismo (así es como funciona
  /// `createUserWithEmailAndPassword`: inicia sesión automáticamente con
  /// la cuenta que acaba de crear). Para evitarlo, todo este registro
  /// ocurre en una app de Firebase secundaria y temporal — el maestro
  /// nunca deja de estar en su propia sesión.
  Future<void> registrarAcudienteConNinoDesdeServidor({
    required String correo,
    required String password,
    required Acudiente acudiente,
    required Nino nino,
    required String parentescoTipo,
    Uint8List? fotoAcudienteBytes,
    String? fotoAcudienteExt,
    Uint8List? fotoNinoBytes,
    String? fotoNinoExt,
  }) async {
    final app = await Firebase.initializeApp(
      name: 'registroTemporal-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    final firestore = FirebaseFirestore.instanceFor(app: app);
    final storage = FirebaseStorage.instanceFor(app: app);

    UserCredential? credential;
    try {
      credential = await auth.createUserWithEmailAndPassword(
        email: correo.trim(),
        password: password,
      );
      final uid = credential.user!.uid;

      String fotoAcudienteUrl = '';
      if (fotoAcudienteBytes != null && fotoAcudienteExt != null) {
        final ref = storage.ref('acudientes_fotos/$uid/foto.$fotoAcudienteExt');
        await ref.putData(fotoAcudienteBytes);
        fotoAcudienteUrl = await ref.getDownloadURL();
      }
      String fotoNinoUrl = '';
      if (fotoNinoBytes != null && fotoNinoExt != null) {
        final ref = storage.ref(
          'ninos_fotos/${nino.documentoIdentificacion}/foto.$fotoNinoExt',
        );
        await ref.putData(fotoNinoBytes);
        fotoNinoUrl = await ref.getDownloadURL();
      }

      final batch = firestore.batch();
      batch.set(firestore.collection('usuarios').doc(uid), {
        'correo': correo.trim(),
        'nombre': acudiente.nombres,
        'apellido': acudiente.apellidos,
        'rol': RolUsuario.usuarioExterno.valorFirestore,
        'activo': true,
        'creadoEn': FieldValue.serverTimestamp(),
      });
      batch.set(firestore.collection('acudientes').doc(uid), {
        ...acudiente.toFirestore(),
        if (fotoAcudienteUrl.isNotEmpty) 'fotoSeguridadUrl': fotoAcudienteUrl,
      });
      batch.set(
        firestore
            .collection('acudientes_documentos')
            .doc(acudiente.numeroDocumento),
        {'uid': uid},
      );
      batch.set(
        firestore.collection('ninos').doc(nino.documentoIdentificacion),
        {
          ...nino.toFirestore(),
          if (fotoNinoUrl.isNotEmpty) 'fotoUrl': fotoNinoUrl,
        },
      );
      batch.set(
        firestore
            .collection('ninos_busqueda')
            .doc(nino.documentoIdentificacion),
        NinoBusqueda(
          documentoIdentificacion: nino.documentoIdentificacion,
          nombres: nino.nombres,
          apellidos: nino.apellidos,
          fechaNacimiento: nino.fechaNacimiento,
        ).toFirestore(),
      );
      batch.set(
        firestore
            .collection('nino_acudiente')
            .doc('${nino.documentoIdentificacion}_$uid'),
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
      if (e.code == 'email-already-in-use') {
        throw const AuthException(
          'Ya existe una cuenta con este correo. Pídele a la familia que '
          'inicie sesión y use "Mis hijos" para registrar niños.',
        );
      }
      throw AuthException(_mensajeDeErrorRegistro(e.code));
    } catch (e) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {
          // Nada más que hacer: la app secundaria se elimina igual abajo.
        }
      }
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'Este número de documento ya se encuentra registrado en el sistema.',
        );
      }
      throw AuthException('No se pudo completar el registro: $e');
    } finally {
      try {
        await auth.signOut();
      } catch (_) {}
      try {
        await app.delete();
      } catch (_) {}
    }
  }

  /// El perfil de acudiente del usuario logueado, si ya lo tiene. Ser
  /// acudiente es independiente del rol: un administrador o un maestro
  /// también puede tener hijos propios registrados con la misma cuenta.
  Future<Acudiente?> obtenerMiAcudiente() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final doc = await _firestore.collection('acudientes').doc(user.uid).get();
    if (!doc.exists) return null;
    return Acudiente.fromFirestore(user.uid, doc.data()!);
  }

  /// Crea el perfil de acudiente del usuario YA logueado (sin crear una
  /// cuenta nueva ni tocar su rol actual). Es lo que usa, por ejemplo,
  /// un administrador que también quiere registrar a sus propios hijos.
  Future<void> crearPerfilAcudiente({
    required Acudiente acudiente,
    Uint8List? fotoBytes,
    String? fotoExt,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }

    String fotoUrl = '';
    if (fotoBytes != null && fotoExt != null) {
      fotoUrl = await subirFotoAcudiente(fotoBytes, fotoExt);
    }

    final batch = _firestore.batch();
    batch.set(_firestore.collection('acudientes').doc(user.uid), {
      ...acudiente.toFirestore(),
      if (fotoUrl.isNotEmpty) 'fotoSeguridadUrl': fotoUrl,
    });
    batch.set(
      _firestore
          .collection('acudientes_documentos')
          .doc(acudiente.numeroDocumento),
      {'uid': user.uid},
    );

    try {
      await batch.commit();
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'Este número de documento ya se encuentra registrado en el sistema.',
        );
      }
      throw AuthException('No se pudo guardar tu perfil de acudiente: $e');
    }
  }

  /// Crea el perfil de acudiente del usuario logueado reutilizando los
  /// datos que ya tiene como servidor (documento, nombre, teléfono, foto)
  /// — para no pedirle de nuevo información que ya dio, y sobre todo para
  /// no volver a subir la foto: se reutiliza la misma URL de Storage en
  /// vez de duplicar el archivo.
  Future<void> crearPerfilAcudienteDesdeServidor(UsuarioApp usuario) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }

    final acudiente = Acudiente(
      uid: user.uid,
      tipoDocumento: usuario.tipoDocumento,
      numeroDocumento: usuario.numeroDocumento,
      nombres: usuario.nombre,
      apellidos: usuario.apellido,
      telefonoCelular: usuario.telefono,
      correoElectronico: usuario.correo,
      fotoSeguridadUrl: usuario.fotoUrl,
    );

    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('acudientes').doc(user.uid),
      acudiente.toFirestore(),
    );
    batch.set(
      _firestore
          .collection('acudientes_documentos')
          .doc(acudiente.numeroDocumento),
      {'uid': user.uid},
    );

    try {
      await batch.commit();
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'Este número de documento ya se encuentra registrado en el sistema.',
        );
      }
      throw AuthException('No se pudo guardar tu perfil de acudiente: $e');
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

  /// Índice liviano (solo nombre y fecha de nacimiento, ver [NinoBusqueda])
  /// de TODOS los niños registrados, para buscarlos por nombre al
  /// vincularlos. Se trae completo una sola vez y se filtra en el
  /// cliente mientras la persona escribe — es información de bajo riesgo
  /// (sin foto/documento/datos médicos) y el volumen de niños de una
  /// sola congregación es chico, así que no hace falta un motor de
  /// búsqueda con índices por prefijo en Firestore.
  Future<List<NinoBusqueda>> obtenerIndiceBusquedaNinos() async {
    final snap = await _firestore.collection('ninos_busqueda').get();
    return snap.docs
        .map((d) => NinoBusqueda.fromFirestore(d.id, d.data()))
        .toList();
  }

  /// Rellena `ninos_busqueda` para niños que ya existían en `ninos` antes
  /// de que existiera esa colección (o que por cualquier otro motivo
  /// quedaron sin su copia de búsqueda — ej. un futuro script de
  /// importación masiva que se olvide de escribirla). Solo un admin
  /// puede listar TODO `ninos` (ver firestore.rules), así que esta
  /// función es admin-only. Devuelve cuántos niños se reindexaron.
  Future<int> reindexarBusquedaNinos() async {
    final ninosSnap = await _firestore.collection('ninos').get();
    if (ninosSnap.docs.isEmpty) return 0;

    var actualizados = 0;
    // Los batches de Firestore admiten máximo 500 operaciones; se
    // procesa en tandas por si la base de niños llega a crecer bastante.
    for (var i = 0; i < ninosSnap.docs.length; i += 400) {
      final tanda = ninosSnap.docs.skip(i).take(400);
      final batch = _firestore.batch();
      for (final doc in tanda) {
        final nino = Nino.fromFirestore(doc.id, doc.data());
        batch.set(
          _firestore.collection('ninos_busqueda').doc(doc.id),
          NinoBusqueda(
            documentoIdentificacion: doc.id,
            nombres: nino.nombres,
            apellidos: nino.apellidos,
            fechaNacimiento: nino.fechaNacimiento,
          ).toFirestore(),
        );
        actualizados++;
      }
      await batch.commit();
    }
    return actualizados;
  }

  /// Un niño por su documento (o llave interna), o null si no existe.
  Future<Nino?> obtenerNinoPorDocumento(String documentoIdentificacion) async {
    final doc = await _firestore
        .collection('ninos')
        .doc(documentoIdentificacion)
        .get();
    if (!doc.exists) return null;
    return Nino.fromFirestore(doc.id, doc.data()!);
  }

  /// La relación del acudiente logueado con un niño puntual (si tiene
  /// una) — con esto se decide si puede editar la ficha del niño: solo
  /// si su `parentescoTipo` es Padre o Madre (decisión de Rafael). El ID
  /// de `nino_acudiente` es determinístico (`{fkIdNino}_{uid}`), así que
  /// esto es una sola lectura directa, no una consulta.
  Future<NinoAcudiente?> obtenerMiRelacionConNino(String fkIdNino) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _firestore
        .collection('nino_acudiente')
        .doc('${fkIdNino}_${user.uid}')
        .get();
    if (!doc.exists) return null;
    return NinoAcudiente.fromFirestore(doc.id, doc.data()!);
  }

  /// Migra relaciones `nino_acudiente` viejas (creadas con ID aleatorio,
  /// antes de 2026-08-14) al esquema nuevo determinístico
  /// (`{fkIdNino}_{fkIdAcudiente}`, ver `esPadreOMadreDe()` en
  /// firestore.rules) — sin esto, un padre/madre vinculado ANTES de ese
  /// cambio no podría editar la ficha de su hijo, porque la relación no
  /// se encontraría en la ruta que las reglas esperan. Admin-only.
  /// Devuelve cuántas relaciones se migraron.
  Future<int> migrarRelacionesADeterministico() async {
    final snap = await _firestore.collection('nino_acudiente').get();
    if (snap.docs.isEmpty) return 0;

    var migrados = 0;
    for (var i = 0; i < snap.docs.length; i += 400) {
      final tanda = snap.docs.skip(i).take(400);
      final batch = _firestore.batch();
      for (final doc in tanda) {
        final data = doc.data();
        final ninoId = data['fk_idNino'] as String?;
        final acudienteUid = data['fk_idAcudiente'] as String?;
        if (ninoId == null || acudienteUid == null) continue;
        final nuevoId = '${ninoId}_$acudienteUid';
        if (doc.id == nuevoId) continue;
        batch.set(_firestore.collection('nino_acudiente').doc(nuevoId), data);
        batch.delete(doc.reference);
        migrados++;
      }
      await batch.commit();
    }
    return migrados;
  }

  /// Completa el documento de un niño que no lo tenía (el "ajuste
  /// inmediato" que pidió Rafael): quien hace el check-in puede
  /// arreglarlo ahí mismo en vez de tener que ir a buscar a un admin.
  /// Las reglas de seguridad solo dejan tocar ESTOS dos campos por esta
  /// vía — nada más del niño se puede cambiar así (ver
  /// `puedeRegistrarAsistencia()` en firestore.rules). El doc ID del
  /// niño (su llave interna) no cambia aunque ahora tenga documento.
  Future<void> completarDocumentoNino({
    required String documentoIdentificacion,
    required String tipoIdentificacion,
    required String identificacionMenor,
  }) async {
    try {
      await _firestore.collection('ninos').doc(documentoIdentificacion).update({
        'tipoIdentificacion': tipoIdentificacion,
        'identificacionMenor': identificacionMenor,
      });
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'No tienes permiso para completar el documento de este niño.',
        );
      }
      throw AuthException('No se pudo guardar el documento: $e');
    }
  }

  /// Edita los datos básicos de un niño. Las reglas de seguridad
  /// permiten esto al padre/madre vinculado o a un admin — a propósito
  /// NO incluye `tipoIdentificacion`/`identificacionMenor` (cambiar el
  /// documento del menor cambiaría su llave primaria, una migración más
  /// delicada) ni `estadoRegistro`/`fotoUrl` (esos quedan admin-only).
  Future<void> editarNino({
    required String documentoIdentificacion,
    required String nombres,
    required String apellidos,
    required DateTime fechaNacimiento,
    required String genero,
    required bool autorizoFotoFlag,
    required bool alertaMedicaFlag,
    required String condicionMedica,
  }) async {
    try {
      await _firestore.collection('ninos').doc(documentoIdentificacion).update({
        'nombres': nombres,
        'apellidos': apellidos,
        'fechaNacimiento': Timestamp.fromDate(fechaNacimiento),
        'genero': genero,
        'autorizoFotoFlag': autorizoFotoFlag,
        'alertaMedicaFlag': alertaMedicaFlag,
        'condicionMedica': alertaMedicaFlag ? condicionMedica : '',
      });
      await _firestore
          .collection('ninos_busqueda')
          .doc(documentoIdentificacion)
          .update({
            'nombres': nombres,
            'apellidos': apellidos,
            'fechaNacimiento': Timestamp.fromDate(fechaNacimiento),
          });
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'No tienes permiso para editar la información de este niño.',
        );
      }
      throw AuthException('No se pudo guardar: $e');
    }
  }

  /// El movimiento (Entrada/Salida) más reciente de un niño, si tiene
  /// alguno. Con esto se decide si el próximo botón de check-in debe
  /// decir "Registrar Entrada" o "Registrar Salida" — un niño cuyo
  /// último movimiento fue "Entrada" está adentro; si fue "Salida" (o no
  /// tiene ninguno todavía), está afuera.
  Future<Registro?> obtenerUltimoMovimiento(String fkIdNino) async {
    final snap = await _firestore
        .collection('registros')
        .where('fkIdNino', isEqualTo: fkIdNino)
        .orderBy('fechaMovimiento', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Registro.fromFirestore(snap.docs.first.id, snap.docs.first.data());
  }

  /// Los acudientes autorizados a entregar/retirar a un niño (vía
  /// `nino_acudiente`) — para que quien hace el check-in/check-out
  /// verifique visualmente (foto de seguridad) quién está presente, en
  /// vez de solo confiar en un nombre escrito a mano. Este es el control
  /// de seguridad real del que habla el SOP.
  Future<List<Acudiente>> obtenerAcudientesDeNino(String fkIdNino) async {
    final relaciones = await _firestore
        .collection('nino_acudiente')
        .where('fk_idNino', isEqualTo: fkIdNino)
        .get();

    final acudientes = <Acudiente>[];
    for (final rel in relaciones.docs) {
      final acudienteUid = rel.data()['fk_idAcudiente'] as String?;
      if (acudienteUid == null) continue;
      final doc = await _firestore
          .collection('acudientes')
          .doc(acudienteUid)
          .get();
      if (doc.exists) {
        acudientes.add(Acudiente.fromFirestore(doc.id, doc.data()!));
      }
    }
    return acudientes;
  }

  /// Registra un movimiento de entrada o salida (SOP §3.3). El uid y
  /// nombre de quien registra los pone esta función (no el llamador),
  /// para que siempre coincidan con la sesión real — así lo exige
  /// también `firestore.rules`.
  Future<void> registrarMovimiento(Registro registro) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final datos = registro.toFirestore()
      ..['fkIdServidor'] = user.uid
      ..['nombreServidor'] = registro.nombreServidor;
    await _firestore.collection('registros').add(datos);
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
      throw const AuthException(
        'No se encontró ningún niño con ese documento.',
      );
    }
    final nino = Nino.fromFirestore(ninoDoc.id, ninoDoc.data()!);

    // El ID de la relación es determinístico (niño_acudiente), así que
    // un segundo intento de vincular al mismo niño cae en "update" (no
    // permitido) en vez de crear un duplicado — mismo patrón que ninos
    // y acudientes_documentos.
    try {
      await _firestore
          .collection('nino_acudiente')
          .doc('${docId}_${user.uid}')
          .set(
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
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException('Ya estás vinculado a este niño.');
      }
      rethrow;
    }
    return nino;
  }

  /// Registra un niño NUEVO y lo vincula al acudiente logueado (para
  /// cuando ya tiene cuenta y quiere agregar otro hijo).
  Future<void> registrarNinoAdicional({
    required Nino nino,
    required String parentescoTipo,
    Uint8List? fotoNinoBytes,
    String? fotoNinoExt,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }

    String fotoNinoUrl = '';
    if (fotoNinoBytes != null && fotoNinoExt != null) {
      fotoNinoUrl = await subirFotoNino(
        nino.documentoIdentificacion,
        fotoNinoBytes,
        fotoNinoExt,
      );
    }

    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('ninos').doc(nino.documentoIdentificacion),
      {
        ...nino.toFirestore(),
        if (fotoNinoUrl.isNotEmpty) 'fotoUrl': fotoNinoUrl,
      },
    );
    batch.set(
      _firestore.collection('ninos_busqueda').doc(nino.documentoIdentificacion),
      NinoBusqueda(
        documentoIdentificacion: nino.documentoIdentificacion,
        nombres: nino.nombres,
        apellidos: nino.apellidos,
        fechaNacimiento: nino.fechaNacimiento,
      ).toFirestore(),
    );
    batch.set(
      _firestore
          .collection('nino_acudiente')
          .doc('${nino.documentoIdentificacion}_${user.uid}'),
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

  /// Todos los acudientes registrados, para el panel "Acudientes y
  /// Niños". Puede listar TODO `acudientes` un admin, o cualquier rol
  /// que haga check-in/out (`puedeRegistrarAsistencia()`, ver
  /// firestore.rules) — pedido de Rafael para que líderes/columnas/
  /// maestros también lo vean, no solo el admin.
  Stream<List<Acudiente>> listarAcudientes() {
    return _firestore
        .collection('acudientes')
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((d) => Acudiente.fromFirestore(d.id, d.data()))
                  .toList()
                ..sort(
                  (a, b) => a.nombreCompleto.toLowerCase().compareTo(
                    b.nombreCompleto.toLowerCase(),
                  ),
                ),
        );
  }

  /// Todos los niños registrados, para el panel "Acudientes y Niños".
  /// Mismo permiso ampliado que [listarAcudientes] — admin o cualquier
  /// rol que haga check-in/out.
  Stream<List<Nino>> listarNinosAdmin() {
    return _firestore
        .collection('ninos')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Nino.fromFirestore(d.id, d.data())).toList()
                ..sort(
                  (a, b) => a.nombreCompleto.toLowerCase().compareTo(
                    b.nombreCompleto.toLowerCase(),
                  ),
                ),
        );
  }

  /// Los niños vinculados a un acudiente puntual (misma lógica que
  /// [obtenerMisHijos], pero para CUALQUIER acudiente — usado desde el
  /// panel admin y desde el check-in al mostrar la ficha de un acudiente).
  Future<List<Nino>> obtenerHijosDeAcudiente(String acudienteUid) async {
    final relaciones = await _firestore
        .collection('nino_acudiente')
        .where('fk_idAcudiente', isEqualTo: acudienteUid)
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

  /// Edita los datos de contacto/documento de un acudiente. Las reglas de
  /// seguridad permiten esto al propio acudiente, a un admin, o a quien
  /// hace check-in/out (decisión de Rafael, "para facilitar el proceso")
  /// — en los tres casos, a propósito NUNCA incluye `estadoAutorizacion`
  /// ni `observacionesRestriccion` (esos quedan admin-only, ver
  /// firestore.rules).
  Future<void> editarAcudiente({
    required String uid,
    required String tipoDocumento,
    required String numeroDocumento,
    required String nombres,
    required String apellidos,
    required String telefonoCelular,
    required String correoElectronico,
  }) async {
    try {
      await _firestore.collection('acudientes').doc(uid).update({
        'tipoDocumento': tipoDocumento,
        'numeroDocumento': numeroDocumento,
        'nombres': nombres,
        'apellidos': apellidos,
        'telefonoCelular': telefonoCelular,
        'correoElectronico': correoElectronico,
      });
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'No tienes permiso para editar la información de este acudiente.',
        );
      }
      throw AuthException('No se pudo guardar: $e');
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
    return _firestore.collection('usuarios').doc(user.uid).snapshots().map((
      doc,
    ) {
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
    return _firestore
        .collection('usuarios')
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((d) => UsuarioApp.fromFirestore(d.id, d.data()))
                  .toList()
                ..sort(
                  (a, b) => a.nombreCompleto.toLowerCase().compareTo(
                    b.nombreCompleto.toLowerCase(),
                  ),
                ),
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
        'fechaVerificacionAntecedentes': Timestamp.fromDate(
          fechaVerificacionAntecedentes,
        ),
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

  /// Sube/reemplaza la foto de seguridad del acudiente logueado (se usa
  /// para validar quién retira a un niño) y devuelve la URL.
  Future<String> subirFotoAcudiente(Uint8List bytes, String extension) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final ref = _storage.ref('acudientes_fotos/${user.uid}/foto.$extension');
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  /// Sube la foto de un niño (solo la primera vez — ver storage.rules) y
  /// devuelve la URL.
  Future<String> subirFotoNino(
    String ninoDocId,
    Uint8List bytes,
    String extension,
  ) async {
    if (_auth.currentUser == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final ref = _storage.ref('ninos_fotos/$ninoDocId/foto.$extension');
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

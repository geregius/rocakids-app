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

  /// Todos los niños registrados, en una sola lectura (no reactivo) —
  /// para cruzar contra "presentes hoy" sin mantener un listener abierto
  /// todo el tiempo que dura el servicio. Mismo permiso que
  /// [listarNinosAdmin] (`allow list`: admin o `puedeRegistrarAsistencia()`).
  Future<List<Nino>> obtenerTodosLosNinos() async {
    final snap = await _firestore.collection('ninos').get();
    return snap.docs.map((d) => Nino.fromFirestore(d.id, d.data())).toList();
  }

  /// Movimientos de entrada/salida del día de HOY (hora local del
  /// dispositivo), para la vista "Niños presentes hoy". Reactivo: se
  /// actualiza solo a medida que se registran entradas/salidas durante
  /// el servicio. Mismo permiso que [registrarMovimiento] para leer
  /// (`puedeRegistrarAsistencia()`).
  Stream<List<Registro>> registrosDeHoy() {
    final ahora = DateTime.now();
    final inicio = DateTime(ahora.year, ahora.month, ahora.day);
    final fin = inicio.add(const Duration(days: 1));
    return _firestore
        .collection('registros')
        .where(
          'fechaMovimiento',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicio),
        )
        .where('fechaMovimiento', isLessThan: Timestamp.fromDate(fin))
        .orderBy('fechaMovimiento')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Registro.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  /// Todas las Entradas registradas desde [desde] (inclusive) hasta hoy —
  /// para el bloque "Histórico" del Dashboard. Consulta directa de una
  /// sola vez (no reactiva): con el volumen actual de registros es
  /// suficientemente rápida; si en el futuro se vuelve lenta, resolver
  /// con una tabla de resúmenes pre-calculados (mismo patrón que el
  /// cierre automático en `functions/index.js`) — no antes, sería
  /// sobre-ingeniería para el volumen de hoy (decisión 2026-08-17).
  Future<List<Registro>> obtenerEntradasDesde(DateTime desde) async {
    final snap = await _firestore
        .collection('registros')
        .where('tipoMovimiento', isEqualTo: 'Entrada')
        .where(
          'fechaMovimiento',
          isGreaterThanOrEqualTo: Timestamp.fromDate(desde),
        )
        .orderBy('fechaMovimiento')
        .get();
    return snap.docs
        .map((d) => Registro.fromFirestore(d.id, d.data()))
        .toList();
  }

  /// Niños/acudientes con algún dato pendiente — para el bloque
  /// "Pendientes" del Dashboard (2026-08-18, pedido de Rafael): un dato
  /// interactivo por categoría, que al tocarlo muestra la lista exacta
  /// de quiénes son. Mismo permiso que el resto de conteos del
  /// Dashboard (`puedeVerInfoLiderazgo()` para acudientes; `ninos` es
  /// más abierto pero el Dashboard igual acota quién ve esta pantalla).
  Future<int> contarNinosSinFoto() async {
    final snap = await _firestore
        .collection('ninos')
        .where('fotoUrl', isEqualTo: '')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<List<Nino>> obtenerNinosSinFoto() async {
    final snap = await _firestore
        .collection('ninos')
        .where('fotoUrl', isEqualTo: '')
        .get();
    return snap.docs.map((d) => Nino.fromFirestore(d.id, d.data())).toList()
      ..sort((a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()));
  }

  Future<int> contarNinosSinDocumento() async {
    final snap = await _firestore
        .collection('ninos')
        .where('identificacionMenor', isEqualTo: '')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<List<Nino>> obtenerNinosSinDocumento() async {
    final snap = await _firestore
        .collection('ninos')
        .where('identificacionMenor', isEqualTo: '')
        .get();
    return snap.docs.map((d) => Nino.fromFirestore(d.id, d.data())).toList()
      ..sort((a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()));
  }

  Future<int> contarAcudientesSinFoto() async {
    final snap = await _firestore
        .collection('acudientes')
        .where('fotoSeguridadUrl', isEqualTo: '')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<List<Acudiente>> obtenerAcudientesSinFoto() async {
    final snap = await _firestore
        .collection('acudientes')
        .where('fotoSeguridadUrl', isEqualTo: '')
        .get();
    return snap.docs.map((d) => Acudiente.fromFirestore(d.id, d.data())).toList()
      ..sort((a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()));
  }

  Future<int> contarAcudientesConCorreoPendiente() async {
    final snap = await _firestore
        .collection('acudientes')
        .where('correoPendienteDeCorregir', isEqualTo: true)
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<List<Acudiente>> obtenerAcudientesConCorreoPendiente() async {
    final snap = await _firestore
        .collection('acudientes')
        .where('correoPendienteDeCorregir', isEqualTo: true)
        .get();
    return snap.docs.map((d) => Acudiente.fromFirestore(d.id, d.data())).toList()
      ..sort((a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()));
  }

  /// Cuántos niños se han "graduado" del ministerio infantil (más de
  /// [edadMaximaRegistro] años, `estadoRegistro == 'Graduado'`) — para
  /// el Dashboard, pedido de Rafael 2026-08-18: "mostrar niños que
  /// estuvieron en RocaKids y ya se graduaron".
  Future<int> contarNinosGraduados() async {
    final snap = await _firestore
        .collection('ninos')
        .where('estadoRegistro', isEqualTo: 'Graduado')
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Niños todavía "Activo" que cumplen [edadMaximaRegistro] + 1 años
  /// ESTE MES (es decir, se gradúan este mes) — alerta mensual pedida
  /// por Rafael 2026-08-18 para poder pasarlos al siguiente nivel de la
  /// iglesia a tiempo. No hay Cloud Function ni campo pre-calculado: se
  /// computa al vuelo cada vez que se abre el Dashboard, cruzando todos
  /// los niños "Activo" contra su fecha de nacimiento (mismo volumen que
  /// [obtenerTodosLosNinos], barato con el tamaño actual de la base).
  Future<List<Nino>> obtenerNinosQueGraduanEsteMes() async {
    final snap = await _firestore
        .collection('ninos')
        .where('estadoRegistro', isEqualTo: 'Activo')
        .get();
    final hoy = DateTime.now();
    return snap.docs
        .map((d) => Nino.fromFirestore(d.id, d.data()))
        .where((n) =>
            n.fechaNacimiento.month == hoy.month &&
            hoy.year - n.fechaNacimiento.year == edadMaximaRegistro + 1)
        .toList();
  }

  /// Niños "Activo" que cumplieron años en los últimos 7 días (o cumplen
  /// hoy) — vista "Cumpleaños" (2026-08-18, pedido de Rafael) y aviso al
  /// registrar su ingreso. Mismo criterio y volumen que
  /// [obtenerNinosQueGraduanEsteMes]: se computa al vuelo comparando mes
  /// y día contra hoy, sin importar el año.
  Future<List<Nino>> obtenerNinosQueCumplieronEstaSemana() async {
    final snap = await _firestore
        .collection('ninos')
        .where('estadoRegistro', isEqualTo: 'Activo')
        .get();
    return snap.docs
        .map((d) => Nino.fromFirestore(d.id, d.data()))
        .where((n) => cumpleEnUltimaSemana(n.fechaNacimiento))
        .toList();
  }

  /// Cuántos niños hay hoy en el sistema (colección `ninos` completa) —
  /// estadística simple para el Dashboard. No es una tendencia en el
  /// tiempo porque los documentos de `ninos` no guardan fecha de
  /// creación; ver docstring de [DashboardScreen] para el detalle.
  Future<int> contarNinosRegistrados() async {
    final snap = await _firestore.collection('ninos').count().get();
    return snap.count ?? 0;
  }

  /// Cuántos acudientes hay hoy en el sistema — mismo permiso que
  /// `listarAcudientes()` (`puedeVerInfoLiderazgo()` en firestore.rules:
  /// administrador, columna, líder de ministerio).
  Future<int> contarAcudientesRegistrados() async {
    final snap = await _firestore.collection('acudientes').count().get();
    return snap.count ?? 0;
  }

  /// Cuántos servidores activos hay (roles operativos del ministerio,
  /// `activo == true`). Mismo permiso que [contarAcudientesRegistrados]
  /// (`puedeVerInfoLiderazgo()` en firestore.rules): administrador,
  /// columna y líder de ministerio. Rafael confirmó explícitamente
  /// (2026-08-18) que columna y líder de ministerio SÍ pueden ver la
  /// información de los servidores — solo líder de escuela de siervos
  /// (y el resto de roles operativos) no, y esos de todas formas no
  /// tienen acceso al Dashboard (`RolUsuario.puedeVerDashboard`).
  Future<int> contarServidoresActivos() async {
    final rolesDeServidor = RolUsuario.values
        .where((r) => r.esRolDeServidor)
        .map((r) => r.valorFirestore)
        .toList();
    final snap = await _firestore
        .collection('usuarios')
        .where('rol', whereIn: rolesDeServidor)
        .where('activo', isEqualTo: true)
        .count()
        .get();
    return snap.count ?? 0;
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

  /// Cuántas veces un niño ha tenido Entrada en los últimos 30 días —
  /// para la alerta reforzada en `registro_asistencia_screen.dart`
  /// cuando el niño sigue sin documento (2026-08-17, pedido de Rafael:
  /// ya no se bloquea el registro sin documento, pero si se repite
  /// mucho hay que insistir más en conseguirlo).
  Future<int> contarEntradasUltimoMes(String fkIdNino) async {
    final desde = DateTime.now().subtract(const Duration(days: 30));
    final snap = await _firestore
        .collection('registros')
        .where('fkIdNino', isEqualTo: fkIdNino)
        .where('tipoMovimiento', isEqualTo: 'Entrada')
        .where('fechaMovimiento', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .get();
    return snap.docs.length;
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
  ///
  /// Junto con el registro (mismo batch atómico), actualiza
  /// `ninos/{fkIdNino}.presente` — así `firestore.rules` puede rechazar
  /// una SEGUNDA Entrada para un niño que ya está presente (pedido de
  /// Rafael, 2026-08-17), incluso si dos servidores lo registran casi al
  /// mismo tiempo. No aplica a niños visitante (no tienen doc en `ninos`).
  Future<void> registrarMovimiento(Registro registro) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final datos = registro.toFirestore()
      ..['fkIdServidor'] = user.uid
      ..['nombreServidor'] = registro.nombreServidor;

    final batch = _firestore.batch();
    batch.set(_firestore.collection('registros').doc(), datos);
    if (registro.fkIdNino.isNotEmpty) {
      batch.update(_firestore.collection('ninos').doc(registro.fkIdNino), {
        'presente': registro.tipoMovimiento == 'Entrada',
      });
    }
    try {
      await batch.commit();
    } catch (e) {
      if (e.toString().contains('permission-denied') &&
          registro.tipoMovimiento == 'Entrada') {
        throw const AuthException(
          'Este niño ya tiene una entrada activa — puede que ya lo haya '
          'registrado otra persona. Actualiza la pantalla e intenta de nuevo.',
        );
      }
      rethrow;
    }
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

  /// Registra un niño NUEVO y lo vincula a un acudiente. Por defecto es
  /// al acudiente logueado (para cuando ya tiene cuenta y quiere agregar
  /// otro hijo, desde su propio portal) — pero un servidor puede pasar
  /// [acudienteUid] explícito para hacerlo en nombre de OTRO acudiente
  /// que ya tiene cuenta (ej. "Registrar familia" cuando el acudiente ya
  /// existe pero el niño es nuevo). En ese segundo caso hace falta el
  /// permiso ampliado de `puedeRegistrarAsistencia()` en `nino_acudiente`
  /// (ver firestore.rules) — el propio acudiente siempre puede para sí
  /// mismo.
  Future<void> registrarNinoAdicional({
    required Nino nino,
    required String parentescoTipo,
    String? acudienteUid,
    Uint8List? fotoNinoBytes,
    String? fotoNinoExt,
  }) async {
    final uid = acudienteUid ?? _auth.currentUser?.uid;
    if (uid == null) {
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

  /// Busca un acudiente que YA tiene cuenta por su número de documento —
  /// para "Registrar familia" cuando el acudiente ya existe y solo hace
  /// falta agregarle un niño (nuevo o existente), sin duplicar su
  /// cuenta. `null` si no se encuentra. No hay búsqueda por nombre para
  /// acudientes (a propósito, por privacidad — no existe un
  /// `acudientes_busqueda` como sí existe `ninos_busqueda`).
  Future<Acudiente?> buscarAcudientePorDocumento(String numeroDocumento) async {
    final numero = numeroDocumento.trim();
    if (numero.isEmpty) return null;
    final refDoc = await _firestore
        .collection('acudientes_documentos')
        .doc(numero)
        .get();
    if (!refDoc.exists) return null;
    final uid = refDoc.data()?['uid'] as String?;
    if (uid == null) return null;
    final acudienteDoc = await _firestore.collection('acudientes').doc(uid).get();
    if (!acudienteDoc.exists) return null;
    return Acudiente.fromFirestore(uid, acudienteDoc.data()!);
  }

  /// Vincula un acudiente y un niño que YA EXISTEN ambos en el sistema
  /// (ej. "Registrar familia" cuando ninguno de los dos es nuevo, solo
  /// faltaba la relación entre ellos). Requiere el permiso ampliado de
  /// `puedeRegistrarAsistencia()` en `nino_acudiente` (ver
  /// firestore.rules) para vincular a un acudiente que no es quien llama.
  Future<void> vincularNinoAcudienteExistentes({
    required String documentoNino,
    required String acudienteUid,
    required String parentescoTipo,
  }) async {
    final ninoDoc = await _firestore.collection('ninos').doc(documentoNino).get();
    if (!ninoDoc.exists) {
      throw const AuthException('No se encontró el niño.');
    }
    final nino = Nino.fromFirestore(ninoDoc.id, ninoDoc.data()!);

    try {
      await _firestore
          .collection('nino_acudiente')
          .doc('${documentoNino}_$acudienteUid')
          .set(
            NinoAcudiente(
              id: '',
              fkIdNino: documentoNino,
              fkIdAcudiente: acudienteUid,
              parentescoTipo: parentescoTipo,
              autorizacionFormulario: 'Sí',
              autorizacionImagen: nino.autorizoFotoFlag ? 'Sí' : 'No',
              esRepresentanteLegalFlag: false,
            ).toFirestore(),
          );
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'Este acudiente ya está vinculado a este niño.',
        );
      }
      rethrow;
    }
  }

  /// Lo mismo que [registrarAcudienteConNinoDesdeServidor], pero para
  /// cuando el ACUDIENTE es nuevo y el NIÑO ya existe en el sistema (ej.
  /// "Registrar familia" cuando el papá quiere su propia cuenta para un
  /// niño que ya registró la mamá). Mismo truco de la app de Firebase
  /// secundaria y temporal para no perder la sesión de quien llama.
  Future<void> vincularAcudienteNuevoANinoExistenteDesdeServidor({
    required String correo,
    required String password,
    required Acudiente acudiente,
    required String documentoNino,
    required String parentescoTipo,
    Uint8List? fotoAcudienteBytes,
    String? fotoAcudienteExt,
  }) async {
    // Se valida ANTES de crear la cuenta nueva, con la sesión propia de
    // quien llama — así, si el documento del niño está mal escrito, no
    // queda una cuenta huérfana que haya que borrar después.
    final ninoDoc = await _firestore.collection('ninos').doc(documentoNino).get();
    if (!ninoDoc.exists) {
      throw const AuthException(
        'No se encontró ningún niño con ese documento.',
      );
    }
    final nino = Nino.fromFirestore(ninoDoc.id, ninoDoc.data()!);

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
        firestore.collection('nino_acudiente').doc('${documentoNino}_$uid'),
        NinoAcudiente(
          id: '',
          fkIdNino: documentoNino,
          fkIdAcudiente: uid,
          parentescoTipo: parentescoTipo,
          autorizacionFormulario: 'Sí',
          autorizacionImagen: nino.autorizoFotoFlag ? 'Sí' : 'No',
          esRepresentanteLegalFlag: false,
        ).toFirestore(),
      );
      await batch.commit();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw const AuthException(
          'Ya existe una cuenta con este correo. Pídele a la familia que '
          'inicie sesión y use "Mis hijos" para vincularse a este niño.',
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
        // Se recalcula solo: en cuanto quede un correo escrito, se apaga
        // la alerta de "correo pendiente de corregir" (ver [Acudiente]).
        'correoPendienteDeCorregir': correoElectronico.trim().isEmpty,
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

  /// Cambia la contraseña del usuario LOGUEADO (no se puede cambiar la de
  /// otro con el SDK de cliente — solo Admin SDK, que este proyecto no
  /// usa para esto). Pide la contraseña actual para reautenticar primero
  /// — Firebase Auth exige una sesión "reciente" para operaciones
  /// sensibles como esta, y a los pocos minutos de haber iniciado sesión
  /// ya no cuenta como reciente.
  Future<void> cambiarPassword({
    required String passwordActual,
    required String passwordNueva,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthException('No hay sesión activa.');
    }
    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: passwordActual,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(passwordNueva);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          throw const AuthException('La contraseña actual no es correcta.');
        case 'weak-password':
          throw const AuthException(
            'La contraseña nueva es muy débil (mínimo 6 caracteres).',
          );
        case 'requires-recent-login':
          throw const AuthException(
            'Por seguridad, cierra sesión y vuelve a entrar antes de '
            'cambiar tu contraseña.',
          );
        case 'too-many-requests':
          throw const AuthException(
            'Demasiados intentos. Intenta de nuevo en unos minutos.',
          );
        default:
          throw AuthException('No se pudo cambiar la contraseña: ${e.message}');
      }
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

  /// Elimina la cuenta de un servidor (2026-08-18, pedido de Rafael) —
  /// **solo admin** (impuesto también en `firestore.rules`, `usuarios`
  /// ya tenía `allow delete: if esAdmin()`). Solo borra su documento en
  /// `usuarios` (quita su acceso a la app de inmediato); su cuenta de
  /// Firebase Auth NO se borra — el SDK de cliente no puede borrar la
  /// cuenta de OTRO usuario, solo la propia. Si esa misma persona
  /// también es acudiente (`acudientes/{uid}`), eso NO se toca — son
  /// registros independientes.
  Future<void> eliminarServidor(String uid) {
    return _firestore.collection('usuarios').doc(uid).delete();
  }

  /// Elimina a un niño y todo lo que depende directamente de su
  /// identidad: sus relaciones con acudientes (`nino_acudiente`) y su
  /// entrada en el índice de búsqueda (`ninos_busqueda`). A propósito
  /// NO borra sus `registros` históricos de asistencia — quedan como
  /// dato histórico aunque el niño ya no exista. **Solo admin**.
  Future<void> eliminarNino(String documentoIdentificacion) async {
    final relaciones = await _firestore
        .collection('nino_acudiente')
        .where('fk_idNino', isEqualTo: documentoIdentificacion)
        .get();
    final batch = _firestore.batch();
    for (final doc in relaciones.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_firestore.collection('ninos_busqueda').doc(documentoIdentificacion));
    batch.delete(_firestore.collection('ninos').doc(documentoIdentificacion));
    await batch.commit();
  }

  /// Elimina a un acudiente y todo lo que depende directamente de su
  /// identidad: sus relaciones con niños (`nino_acudiente`) y la reserva
  /// de unicidad de su documento (`acudientes_documentos`). A propósito
  /// NO borra `usuarios/{uid}` ni su cuenta de Firebase Auth — si esa
  /// misma persona también es servidor, no debe perder su acceso por
  /// esto; si es un acudiente puro, el documento de `usuarios` queda
  /// huérfano pero inofensivo (sin `acudientes/{uid}`, "Mis hijos" le
  /// pediría llenar el formulario de nuevo si volviera a entrar).
  /// **Solo admin**.
  Future<void> eliminarAcudiente(String uid) async {
    final doc = await _firestore.collection('acudientes').doc(uid).get();
    final numeroDocumento = doc.data()?['numeroDocumento'] as String?;
    final relaciones = await _firestore
        .collection('nino_acudiente')
        .where('fk_idAcudiente', isEqualTo: uid)
        .get();
    final batch = _firestore.batch();
    for (final rel in relaciones.docs) {
      batch.delete(rel.reference);
    }
    if (numeroDocumento != null && numeroDocumento.isNotEmpty) {
      batch.delete(_firestore.collection('acudientes_documentos').doc(numeroDocumento));
    }
    batch.delete(_firestore.collection('acudientes').doc(uid));
    await batch.commit();
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

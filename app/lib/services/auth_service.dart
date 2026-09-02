import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../models/acudiente.dart';
import '../models/gestion.dart';
import '../models/grupo_servidores.dart';
import '../models/manual_contenido.dart';
import '../models/nino.dart';
import '../models/no_autorizado.dart';
import '../models/registro.dart';
import '../models/usuario_app.dart';
import '../models/video_tutorial.dart';

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

  // Caché en memoria del índice de búsqueda de niños (`static`, no de
  // instancia: cada pantalla crea su propio `AuthService()`, así que
  // solo una caché compartida por la app entera evita repetir la
  // descarga completa). Vencimiento corto (no invalidación explícita
  // al registrar un niño nuevo) — un niño recién registrado puede
  // tardar hasta 5 minutos en aparecer en la búsqueda desde OTRA
  // sesión ya abierta, aceptable frente a lo simple que queda el
  // código (encontrado 2026-08-19: "Registro de asistencia" se sentía
  // lento en celular, sobre todo si el servidor entraba y salía de la
  // pantalla varias veces en el mismo turno).
  static List<NinoBusqueda>? _cacheIndiceBusqueda;
  static DateTime? _cacheIndiceBusquedaHora;
  static const _ttlIndiceBusqueda = Duration(minutes: 5);

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

  /// URL de la Cloud Function invocable `enviarCorreoRecuperacion`
  /// (`app/functions/index.js`, región `us-central1` por defecto).
  static const _urlCorreoRecuperacion =
      'https://us-central1-rocakidsarmenia-7935b.cloudfunctions.net/enviarCorreoRecuperacion';

  /// Pide el correo de recuperación de contraseña — personalizado en
  /// español con la marca de RocaKids (Cloud Function
  /// `enviarCorreoRecuperacion`, mismo Gmail que el correo de
  /// cumpleaños) en vez del correo genérico de Firebase Auth. Nunca
  /// lanza error por "correo no encontrado": no revelamos si un correo
  /// está o no registrado en el sistema.
  ///
  /// Se llama por HTTP directo (protocolo de "función invocable" de
  /// Firebase: `POST {"data": {...}}` → `{"result": {...}}`) en vez de
  /// con el paquete `cloud_functions` — ese paquete tiene un bug
  /// conocido y sin resolver en Flutter Web (falla antes de intentar
  /// la llamada de red, ver firebase/flutterfire#17632).
  Future<void> resetPassword({required String correo}) async {
    try {
      await http.post(
        Uri.parse(_urlCorreoRecuperacion),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': {'correo': correo.trim()},
        }),
      );
    } catch (_) {
      throw const AuthException(
        'No se pudo enviar el correo de recuperación. Intenta de nuevo.',
      );
    }
  }

  /// Valida un código de restablecimiento (`oobCode` del enlace del
  /// correo de recuperación) y devuelve el correo asociado, o lanza si
  /// el enlace ya venció o ya se usó.
  Future<String> verificarCodigoRecuperacion(String oobCode) async {
    try {
      return await _auth.verifyPasswordResetCode(oobCode);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mensajeDeErrorCodigoReset(e.code));
    }
  }

  /// Completa el restablecimiento: fija `nuevaPassword` para la cuenta
  /// asociada a `oobCode`. Se usa desde `ResetPasswordScreen`, la
  /// pantalla propia que reemplaza la página genérica de Firebase.
  Future<void> confirmarNuevaPassword({
    required String oobCode,
    required String nuevaPassword,
  }) async {
    try {
      await _auth.confirmPasswordReset(code: oobCode, newPassword: nuevaPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mensajeDeErrorCodigoReset(e.code));
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

  /// Auto-registro: crea SOLO la cuenta de un acudiente nuevo (auth +
  /// perfil), sin vincular ningún niño todavía. A diferencia del
  /// servidor, el acudiente obtiene acceso inmediato (rol
  /// "usuario_externo", sin aprobación de un admin) — a propósito NO usa
  /// una app de Firebase secundaria (a diferencia de
  /// [crearAcudienteNuevoDesdeServidor]): acá no hay ninguna sesión
  /// previa que proteger, la cuenta recién creada SÍ debe quedar como la
  /// sesión activa.
  ///
  /// El wizard de auto-registro (`sign_up_acudiente_screen.dart`,
  /// 2026-08-21, soporte de varios niños) llama esto una sola vez y
  /// luego [registrarNinoAdicional] por cada niño — mismo patrón de
  /// composición que "Registrar familia" en vez de un único método
  /// combinado de "acudiente + un niño".
  Future<String> crearAcudienteNuevo({
    required String correo,
    required String password,
    required Acudiente acudiente,
    Uint8List? fotoAcudienteBytes,
    String? fotoAcudienteExt,
  }) async {
    UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: correo.trim(),
        password: password,
      );
      final uid = credential.user!.uid;

      // La foto se sube aquí (no antes) porque hasta ahora no existía
      // sesión con la que Storage pudiera autorizar la subida.
      String fotoAcudienteUrl = '';
      if (fotoAcudienteBytes != null && fotoAcudienteExt != null) {
        fotoAcudienteUrl = await subirFotoAcudiente(
          fotoAcudienteBytes,
          fotoAcudienteExt,
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
      await batch.commit();
      return uid;
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
      // Si el batch falla (ej. documento ya registrado), no dejamos una
      // cuenta de acceso huérfana sin perfil: la eliminamos para que la
      // persona pueda corregir el dato e intentar de nuevo.
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

  /// Crea SOLO la cuenta de un acudiente nuevo (auth + perfil), hecho por
  /// un SERVIDOR en nombre de una familia — ej. en la mesa de registro de
  /// un servicio. A propósito NO vincula ningún niño todavía: el wizard
  /// de "Registrar familia" (2026-08-21, soporte de varios niños por
  /// registro) resuelve primero el uid del acudiente (este método si es
  /// nuevo, o el ya existente si se encontró por documento) y luego
  /// vincula cada niño por separado con [registrarNinoAdicional] o
  /// [vincularNinoAcudienteExistentes] — así no hace falta un método
  /// combinado por cada combinación de "acudiente nuevo/existente x niño
  /// nuevo/existente x cuántos niños".
  ///
  /// La diferencia clave con crear la cuenta "normal": quien llama YA
  /// tiene su propia sesión abierta (el servidor) y no se puede perder.
  /// Crear la cuenta nueva con la app de Firebase "de siempre" dejaría al
  /// servidor logueado como la familia nueva en vez de como él mismo
  /// (así es como funciona `createUserWithEmailAndPassword`: inicia
  /// sesión automáticamente con la cuenta que acaba de crear). Para
  /// evitarlo, esto ocurre en una app de Firebase secundaria y temporal —
  /// el servidor nunca deja de estar en su propia sesión.
  Future<String> crearAcudienteNuevoDesdeServidor({
    required String correo,
    required String password,
    required Acudiente acudiente,
    Uint8List? fotoAcudienteBytes,
    String? fotoAcudienteExt,
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
        await ref.putData(fotoAcudienteBytes, _metadataDeFoto(fotoAcudienteExt));
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
      await batch.commit();
      return uid;
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
      throw AuthException('No se pudo crear la cuenta del acudiente: $e');
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

  /// Los niños vinculados al acudiente logueado. Las fichas se piden en
  /// paralelo (`Future.wait`), no una por una en un `for` secuencial —
  /// con varios hijos, cada consulta secuencial sumaba su propia latencia
  /// de red una detrás de otra, mismo patrón ya corregido antes en
  /// `registro_asistencia_screen.dart` (ver
  /// [[feature-optimizacion-registro-ingreso]] en la memoria).
  Future<List<Nino>> obtenerMisHijos() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final relaciones = await _firestore
        .collection('nino_acudiente')
        .where('fk_idAcudiente', isEqualTo: user.uid)
        .get();

    final ninoIds = relaciones.docs
        .map((rel) => rel.data()['fk_idNino'] as String?)
        .whereType<String>()
        .toList();
    final ninoDocs = await Future.wait(
      ninoIds.map((id) => _firestore.collection('ninos').doc(id).get()),
    );
    return [
      for (final doc in ninoDocs)
        if (doc.exists) Nino.fromFirestore(doc.id, doc.data()!),
    ];
  }

  /// Índice liviano (solo nombre y fecha de nacimiento, ver [NinoBusqueda])
  /// de TODOS los niños registrados, para buscarlos por nombre al
  /// vincularlos. Se trae completo una sola vez y se filtra en el
  /// cliente mientras la persona escribe — es información de bajo riesgo
  /// (sin foto/documento/datos médicos) y el volumen de niños de una
  /// sola congregación es chico, así que no hace falta un motor de
  /// búsqueda con índices por prefijo en Firestore.
  Future<List<NinoBusqueda>> obtenerIndiceBusquedaNinos() async {
    final cache = _cacheIndiceBusqueda;
    final horaCache = _cacheIndiceBusquedaHora;
    if (cache != null &&
        horaCache != null &&
        DateTime.now().difference(horaCache) < _ttlIndiceBusqueda) {
      return cache;
    }
    final snap = await _firestore.collection('ninos_busqueda').get();
    final indice = snap.docs
        .map((d) => NinoBusqueda.fromFirestore(d.id, d.data()))
        .toList();
    _cacheIndiceBusqueda = indice;
    _cacheIndiceBusquedaHora = DateTime.now();
    return indice;
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

  /// Personas que NO deben tener contacto con este niño (custodias,
  /// órdenes de alejamiento, etc.) — texto libre, ver [NoAutorizado].
  /// Cualquiera que pueda ver la ficha del niño con permiso suficiente
  /// puede leerlas (`firestore.rules`); si no tiene permiso, esta
  /// consulta simplemente falla y el llamador debe tratarlo como "no
  /// hay nada que mostrar" en vez de un error visible.
  Future<List<NoAutorizado>> obtenerNoAutorizados(String ninoId) async {
    final snap = await _firestore
        .collection('ninos')
        .doc(ninoId)
        .collection('no_autorizados')
        .orderBy('fechaRegistro', descending: true)
        .get();
    return snap.docs
        .map((d) => NoAutorizado.fromFirestore(d.id, d.data()))
        .toList();
  }

  /// Agrega una persona no autorizada a la lista de este niño. Solo
  /// liderazgo (admin/columna/líder de ministerio) o el padre/madre
  /// vinculado pueden hacerlo (`firestore.rules`). Actualiza en el mismo
  /// batch `ninos/{ninoId}.tieneNoAutorizados` para que el check-in y
  /// "Menores Recibidos" puedan mostrar la advertencia sin una consulta
  /// extra (ver docstring del campo en `Nino`). "Menores Recibidos" se
  /// renombró a "Menores Registrados" el 2026-08-24.
  Future<void> agregarNoAutorizado({
    required String ninoId,
    required String nombre,
    required String documento,
    required String motivo,
    required String nombreRegistradoPor,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final entrada = NoAutorizado(
      id: '',
      nombre: nombre,
      documento: documento,
      motivo: motivo,
      fkIdRegistradoPor: user.uid,
      nombreRegistradoPor: nombreRegistradoPor,
      fechaRegistro: DateTime.now(),
    );
    final ninoRef = _firestore.collection('ninos').doc(ninoId);
    final batch = _firestore.batch();
    batch.set(ninoRef.collection('no_autorizados').doc(), entrada.toFirestore());
    batch.update(ninoRef, {'tieneNoAutorizados': true});
    try {
      await batch.commit();
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'No tienes permiso para agregar personas no autorizadas a este niño.',
        );
      }
      throw AuthException('No se pudo guardar: $e');
    }
  }

  /// Quita una persona de la lista de no autorizados de este niño.
  /// Recalcula `tieneNoAutorizados` según si quedan otras entradas.
  Future<void> eliminarNoAutorizado({
    required String ninoId,
    required String entradaId,
  }) async {
    final ninoRef = _firestore.collection('ninos').doc(ninoId);
    try {
      await ninoRef.collection('no_autorizados').doc(entradaId).delete();
      final restantes = await ninoRef
          .collection('no_autorizados')
          .limit(1)
          .get();
      await ninoRef.update({'tieneNoAutorizados': restantes.docs.isNotEmpty});
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'No tienes permiso para quitar esta entrada.',
        );
      }
      throw AuthException('No se pudo quitar: $e');
    }
  }

  /// Quita el vínculo entre un niño y un acudiente — SIN borrar ni al
  /// niño ni al acudiente, solo la relación entre ambos (2026-08-19,
  /// pedido de Rafael: un acudiente que vinculó un niño por equivocación
  /// debe poder deshacerlo desde "Mis hijos", y un admin debe poder
  /// hacerlo desde la ficha de cualquier acudiente). El ID de
  /// `nino_acudiente` es determinístico, así que no hace falta ninguna
  /// consulta previa para encontrarlo. `firestore.rules` exige que quien
  /// llama sea admin, o el propio `acudienteUid` de la relación.
  Future<void> eliminarRelacionNinoAcudiente({
    required String ninoId,
    required String acudienteUid,
  }) async {
    try {
      await _firestore
          .collection('nino_acudiente')
          .doc('${ninoId}_$acudienteUid')
          .delete();
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException('No tienes permiso para quitar este vínculo.');
      }
      throw AuthException('No se pudo quitar el vínculo: $e');
    }
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
        'mesDiaNacimiento': mesDiaDe(fechaNacimiento),
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

  /// Solo los niños de [ids] (en vez de la colección completa) — para
  /// "Menores Recibidos" y el bloque "Hoy" del Dashboard, que antes
  /// traían TODOS los ~460 niños (`obtenerTodosLosNinos()`, eliminado
  /// 2026-08-19 por quedar sin uso) solo para cruzar nombre/foto/documento
  /// de los pocos que aparecen en los movimientos de hoy — lento en
  /// celular. `whereIn` de Firestore acepta máximo 30 valores por
  /// consulta, así que si hay más se piden en varios lotes en paralelo.
  /// Mismo permiso que [listarNinosAdmin] (`allow list`: admin o
  /// `puedeRegistrarAsistencia()`).
  Future<List<Nino>> obtenerNinosPorIds(Iterable<String> ids) async {
    final lista = ids.toList();
    if (lista.isEmpty) return [];
    final lotes = <List<String>>[
      for (var i = 0; i < lista.length; i += 30)
        lista.sublist(i, i + 30 > lista.length ? lista.length : i + 30),
    ];
    final snaps = await Future.wait(
      lotes.map(
        (lote) => _firestore
            .collection('ninos')
            .where(FieldPath.documentId, whereIn: lote)
            .get(),
      ),
    );
    return [
      for (final snap in snaps)
        for (final d in snap.docs) Nino.fromFirestore(d.id, d.data()),
    ];
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

  /// Resúmenes mensuales de asistencia — para el bloque "Histórico" del
  /// Dashboard (2026-08-19). Reemplaza traer TODAS las Entradas crudas
  /// (llegó a ser lento en celular con ~3738+ registros tras la
  /// migración): la colección `resumenes_mensuales` tiene un documento
  /// por mes transcurrido (mantenido por la Cloud Function
  /// `actualizarResumenMensual`), así que esta consulta siempre trae un
  /// puñado de documentos chiquitos, sin importar cuántos registros
  /// individuales existan.
  Future<List<ResumenMensual>> obtenerResumenesMensuales() async {
    final snap = await _firestore.collection('resumenes_mensuales').get();
    return snap.docs
        .map((d) => ResumenMensual.fromFirestore(d.id, d.data()))
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
      ..sort(
        (a, b) => a.nombreCompleto.toLowerCase().compareTo(
          b.nombreCompleto.toLowerCase(),
        ),
      );
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
      ..sort(
        (a, b) => a.nombreCompleto.toLowerCase().compareTo(
          b.nombreCompleto.toLowerCase(),
        ),
      );
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
    return snap.docs
        .map((d) => Acudiente.fromFirestore(d.id, d.data()))
        .toList()
      ..sort(
        (a, b) => a.nombreCompleto.toLowerCase().compareTo(
          b.nombreCompleto.toLowerCase(),
        ),
      );
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
    return snap.docs
        .map((d) => Acudiente.fromFirestore(d.id, d.data()))
        .toList()
      ..sort(
        (a, b) => a.nombreCompleto.toLowerCase().compareTo(
          b.nombreCompleto.toLowerCase(),
        ),
      );
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
  /// los niños "Activo" contra su fecha de nacimiento — barato con el
  /// tamaño actual de la base (~460 niños).
  Future<List<Nino>> obtenerNinosQueGraduanEsteMes() async {
    final snap = await _firestore
        .collection('ninos')
        .where('estadoRegistro', isEqualTo: 'Activo')
        .get();
    final hoy = DateTime.now();
    return snap.docs
        .map((d) => Nino.fromFirestore(d.id, d.data()))
        .where(
          (n) =>
              n.fechaNacimiento.month == hoy.month &&
              hoy.year - n.fechaNacimiento.year == edadMaximaRegistro + 1,
        )
        .toList();
  }

  /// Niños "Activo" que cumplieron años en los últimos 7 días (o cumplen
  /// hoy) — vista "Cumpleaños" (2026-08-18, pedido de Rafael) y aviso al
  /// registrar su ingreso. **Acotado por `mesDiaNacimiento`** (2026-08-19,
  /// antes traía TODA la colección `ninos` y filtraba en el cliente —
  /// lento en celular con ~460 documentos completos) — el `where` deja
  /// que Firestore descarte casi todo del lado del servidor.
  Future<List<Nino>> obtenerNinosQueCumplieronEstaSemana() async {
    final snap = await _firestore
        .collection('ninos')
        .where('estadoRegistro', isEqualTo: 'Activo')
        .where('mesDiaNacimiento', whereIn: mesDiaUltimaSemana())
        .get();
    return snap.docs.map((d) => Nino.fromFirestore(d.id, d.data())).toList();
  }

  /// Niños "Activo" con 10 o más Entradas en toda su historia
  /// (`totalEntradas`) cuya última Entrada (`ultimaAsistencia`) fue hace
  /// más de [diasSinAsistir] días — reporte de seguimiento pedido por
  /// Rafael (2026-08-21) para identificar a quiénes dejaron de asistir
  /// después de venir con regularidad. Ordenado por más tiempo ausente
  /// primero. Si el niño vuelve (nueva Entrada), `ultimaAsistencia` se
  /// actualiza de inmediato (ver Cloud Function `actualizarResumenMensual`
  /// en `app/functions/index.js`) y sale de este listado solo — no hay
  /// ningún contador de "días sin venir" que reiniciar a mano.
  ///
  /// `totalEntradas`/`ultimaAsistencia` deben estar poblados con
  /// [backfillEstadisticasAsistencia] para el histórico anterior a
  /// 2026-08-21 — ver docs/estado-proyecto.md.
  Future<List<Nino>> obtenerNinosQueDejaronDeAsistir({
    int diasSinAsistir = 45,
  }) async {
    final snap = await _firestore
        .collection('ninos')
        .where('estadoRegistro', isEqualTo: 'Activo')
        .where('totalEntradas', isGreaterThanOrEqualTo: 10)
        .get();
    final limite = DateTime.now().subtract(Duration(days: diasSinAsistir));
    final ninos = snap.docs
        .map((d) => Nino.fromFirestore(d.id, d.data()))
        .where(
          (n) => n.ultimaAsistencia != null && n.ultimaAsistencia!.isBefore(limite),
        )
        .toList()
      ..sort((a, b) => a.ultimaAsistencia!.compareTo(b.ultimaAsistencia!));
    return ninos;
  }

  /// Backfill de un solo uso: calculó `ninos/{id}.totalEntradas`/
  /// `ultimaAsistencia` para el histórico completo de `registros` ya
  /// existente antes de 2026-08-21 (la Cloud Function
  /// `actualizarResumenMensual` solo mantiene estos campos para
  /// Entradas NUEVAS desde ese cambio). **Ya se corrió** (botón admin
  /// temporal en el Dashboard, quitado tras confirmarlo — mismo
  /// criterio que "Reindexar"/"Migrar vínculos" en su momento, ver
  /// docs/estado-proyecto.md). El método queda en el código por si
  /// hace falta recalcular de nuevo (ej. una migración de datos futura
  /// que traiga `registros` sin pasar por la Cloud Function): es
  /// idempotente, siempre recalcula desde `registros` (la fuente de
  /// verdad), no acumula. **Solo admin** (mismo permiso que editar
  /// `ninos` libremente).
  Future<Map<String, int>> backfillEstadisticasAsistencia() async {
    final snap = await _firestore
        .collection('registros')
        .where('tipoMovimiento', isEqualTo: 'Entrada')
        .get();

    final totalPorNino = <String, int>{};
    final ultimaPorNino = <String, DateTime>{};
    for (final doc in snap.docs) {
      final datos = doc.data();
      final ninoId = datos['fkIdNino'] as String? ?? '';
      if (ninoId.isEmpty) continue; // visitante, sin ficha en `ninos`
      final fecha = (datos['fechaMovimiento'] as Timestamp?)?.toDate();
      if (fecha == null) continue;
      totalPorNino[ninoId] = (totalPorNino[ninoId] ?? 0) + 1;
      final actual = ultimaPorNino[ninoId];
      if (actual == null || fecha.isAfter(actual)) {
        ultimaPorNino[ninoId] = fecha;
      }
    }

    // `eliminarNino()` borra la ficha pero conserva sus `registros`
    // históricos (a propósito, ver docstring) — así que un `fkIdNino` de
    // un niño ya eliminado no debe intentar actualizarse (`.update()`
    // fallaría con NOT_FOUND y tumbaría todo el batch).
    final ninosExistentes = await _firestore.collection('ninos').get();
    final idsExistentes = ninosExistentes.docs.map((d) => d.id).toSet();
    final ninoIds = totalPorNino.keys
        .where((id) => idsExistentes.contains(id))
        .toList();
    const tamanoLote = 400; // margen bajo el límite de 500 escrituras/batch
    for (var i = 0; i < ninoIds.length; i += tamanoLote) {
      final lote = ninoIds.sublist(
        i,
        i + tamanoLote > ninoIds.length ? ninoIds.length : i + tamanoLote,
      );
      final batch = _firestore.batch();
      for (final ninoId in lote) {
        batch.update(_firestore.collection('ninos').doc(ninoId), {
          'totalEntradas': totalPorNino[ninoId],
          'ultimaAsistencia': Timestamp.fromDate(ultimaPorNino[ninoId]!),
        });
      }
      await batch.commit();
    }

    return {
      'ninosActualizados': ninoIds.length,
      'entradasProcesadas': snap.docs.length,
    };
  }

  /// Historial de gestión de un niño (llamadas hechas, resultado, etc.)
  /// — ver docstring de [Gestion]. Orden más reciente primero.
  Future<List<Gestion>> obtenerGestiones(String ninoId) async {
    final snap = await _firestore
        .collection('ninos')
        .doc(ninoId)
        .collection('gestiones')
        .orderBy('fecha', descending: true)
        .get();
    return snap.docs.map((d) => Gestion.fromFirestore(d.id, d.data())).toList();
  }

  /// Registra una gestión de seguimiento sobre un niño (típicamente uno
  /// que dejó de asistir) y deja su `estadoRegistro` en [nuevoEstado]
  /// (`estadosRegistroGestionables`: 'Activo' o 'Inactivo') — mismo
  /// batch atómico, para que la nota y el estado resultante siempre
  /// queden consistentes entre sí. Solo liderazgo (admin/columna/líder
  /// de ministerio) puede llamar esto (`firestore.rules`) — pedido de
  /// Rafael (2026-08-21) para poder "evidenciar" que el reporte de
  /// inasistencia se está gestionando, no solo mirando.
  Future<void> registrarGestion({
    required String ninoId,
    required String nota,
    required String nuevoEstado,
    required String nombreRegistradoPor,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final gestion = Gestion(
      id: '',
      nota: nota,
      estadoResultante: nuevoEstado,
      fkIdRegistradoPor: user.uid,
      nombreRegistradoPor: nombreRegistradoPor,
      fecha: DateTime.now(),
    );
    final ninoRef = _firestore.collection('ninos').doc(ninoId);
    final batch = _firestore.batch();
    batch.set(ninoRef.collection('gestiones').doc(), gestion.toFirestore());
    batch.update(ninoRef, {'estadoRegistro': nuevoEstado});
    try {
      await batch.commit();
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        throw const AuthException(
          'No tienes permiso para registrar una gestión sobre este niño.',
        );
      }
      throw AuthException('No se pudo guardar la gestión: $e');
    }
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

  /// Servidores activos con `perfilCompletoConNacimiento` — para poder
  /// "validar quiénes ya ingresaron a la aplicación" de verdad (pedido
  /// de Rafael, 2026-08-21): con foto Y fecha de nacimiento, no solo
  /// los campos originales del perfil. Mismo permiso/patrón que
  /// [obtenerServidoresQueCumplieronEstaSemana]: el filtro se aplica
  /// del lado del cliente sobre la lista ya acotada a servidores
  /// activos (no toda la colección `usuarios`).
  Future<List<UsuarioApp>> obtenerServidoresConPerfilCompleto() async {
    final rolesDeServidor = RolUsuario.values
        .where((r) => r.esRolDeServidor)
        .map((r) => r.valorFirestore)
        .toList();
    final snap = await _firestore
        .collection('usuarios')
        .where('rol', whereIn: rolesDeServidor)
        .where('activo', isEqualTo: true)
        .get();
    return snap.docs
        .map((d) => UsuarioApp.fromFirestore(d.id, d.data()))
        .where((u) => u.perfilCompletoConNacimiento)
        .toList()
      ..sort(
        (a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()),
      );
  }

  /// Todos los servidores activos (sin filtrar por fecha) — para
  /// "Cumpleaños Servidores" ordenado por proximidad (2026-08-29, pedido
  /// de Rafael: ver a todos ordenados de quién cumple más pronto a quién
  /// más falta, no solo los de la última semana). Misma consulta base
  /// que [obtenerServidoresConPerfilCompleto] (rol whereIn + activo, sin
  /// `whereIn` de fecha) — es una colección chica (~30 servidores
  /// activos), traerla completa y ordenar del lado del cliente es
  /// barato, igual que ya se hacía para ese otro conteo.
  Future<List<UsuarioApp>> obtenerTodosLosServidoresActivos() async {
    final rolesDeServidor = RolUsuario.values
        .where((r) => r.esRolDeServidor)
        .map((r) => r.valorFirestore)
        .toList();
    final snap = await _firestore
        .collection('usuarios')
        .where('rol', whereIn: rolesDeServidor)
        .where('activo', isEqualTo: true)
        .get();
    return snap.docs.map((d) => UsuarioApp.fromFirestore(d.id, d.data())).toList();
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
        .where(
          'fechaMovimiento',
          isGreaterThanOrEqualTo: Timestamp.fromDate(desde),
        )
        .get();
    return snap.docs.length;
  }

  /// El registro más reciente de HOY con este número de manilla (que
  /// puede venir de un QR escaneado), sin importar si es de un niño
  /// registrado o un visitante — para el escaneo de manillas
  /// (2026-08-18, pedido de Rafael). Como cada manilla física es única,
  /// basta con mirar cuál fue el último movimiento de hoy con ese
  /// código: si fue una Entrada, la manilla sigue en uso.
  Future<Registro?> _ultimoMovimientoDeHoyPorManilla(
    String numeroManilla,
  ) async {
    final ahora = DateTime.now();
    final inicio = DateTime(ahora.year, ahora.month, ahora.day);
    final snap = await _firestore
        .collection('registros')
        .where(
          'fechaMovimiento',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicio),
        )
        .where('numeroManilla', isEqualTo: numeroManilla)
        .orderBy('fechaMovimiento', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Registro.fromFirestore(snap.docs.first.id, snap.docs.first.data());
  }

  /// true si esta manilla ya está puesta en alguien presente ahora mismo
  /// — para avisar al escanearla en una Entrada nueva y evitar usar una
  /// manilla que ya estaba en uso.
  Future<bool> manillaEnUsoHoy(String numeroManilla) async {
    final ultimo = await _ultimoMovimientoDeHoyPorManilla(numeroManilla);
    return ultimo != null && ultimo.tipoMovimiento == 'Entrada';
  }

  /// El registro de Entrada de quien está presente ahora mismo con esta
  /// manilla, o `null` si ninguna manilla de hoy coincide o si ya salió
  /// — para dar Salida escaneando directamente la manilla gemela, sin
  /// tener que buscar al niño por nombre.
  Future<Registro?> buscarPresentePorManilla(String numeroManilla) async {
    final ultimo = await _ultimoMovimientoDeHoyPorManilla(numeroManilla);
    if (ultimo == null || ultimo.tipoMovimiento != 'Entrada') return null;
    return ultimo;
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

    // Antes pedía cada acudiente UNO POR UNO (un niño con 3 acudientes
    // hacía 3 round-trips seguidos) — ahora los pide todos a la vez
    // (encontrado 2026-08-19, mismo motivo que el resto de esta sesión:
    // se sentía lento en celular al seleccionar un niño).
    final uids = relaciones.docs
        .map((rel) => rel.data()['fk_idAcudiente'] as String?)
        .whereType<String>()
        .toList();
    final docs = await Future.wait(
      uids.map((uid) => _firestore.collection('acudientes').doc(uid).get()),
    );
    return [
      for (final doc in docs)
        if (doc.exists) Acudiente.fromFirestore(doc.id, doc.data()!),
    ];
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

  /// true si "Modo emergencia" está activo AHORA MISMO — cualquier
  /// autenticado puede leerlo (`estado_app/emergencia`, ver
  /// `firestore.rules`), porque TODA la app reacciona a este valor en
  /// tiempo real (ver `AppShell`, 2026-08-19). `false` si el documento
  /// todavía no existe (nunca se ha activado).
  Stream<bool> emergenciaActivaStream() {
    return _firestore
        .collection('estado_app')
        .doc('emergencia')
        .snapshots()
        .map((doc) => doc.data()?['activo'] as bool? ?? false);
  }

  /// Activa "Modo emergencia" — a partir de este momento, TODA la app
  /// reacciona en tiempo real (ver `emergenciaActivaStream`):
  /// servidores quedan restringidos a la pantalla de emergencia,
  /// acudientes ven un aviso de bloqueo, admin sigue viendo todo normal.
  /// Solo `puedeVerInfoLiderazgo()` (admin/columna/líder de ministerio)
  /// puede llamarlo — impuesto en `firestore.rules`. [nombreActivador]
  /// se pasa desde la UI (mismo patrón que `Registro.nombreServidor`) en
  /// vez de resolverlo del lado del servidor.
  Future<void> activarModoEmergencia(String nombreActivador) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    try {
      await _firestore.collection('estado_app').doc('emergencia').set({
        'activo': true,
        'activadoPorUid': user.uid,
        'activadoPorNombre': nombreActivador,
        'activadoEn': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AuthException('No se pudo activar el modo emergencia: $e');
    }
  }

  /// Desactiva "Modo emergencia" — misma restricción de permiso que
  /// [activarModoEmergencia].
  Future<void> desactivarModoEmergencia() async {
    try {
      await _firestore.collection('estado_app').doc('emergencia').update({
        'activo': false,
      });
    } catch (e) {
      throw AuthException('No se pudo desactivar el modo emergencia: $e');
    }
  }

  /// Registra una Salida durante "Modo emergencia" (2026-08-19, pedido
  /// de Rafael): exige, ADEMÁS de los datos normales de quién retira al
  /// niño (ya armados en [salida] por el llamador — acudiente elegido o
  /// "Otro" escrito a mano, igual que una salida normal), una foto
  /// tomada en el momento y una firma — evidencia extra para el reporte
  /// posterior, porque en una emergencia quien retira al niño puede no
  /// ser la persona de siempre. `modalidadRegistro` se fuerza a
  /// `'Emergencia'` sin importar lo que traiga [salida] (impuesto
  /// también en `firestore.rules`, no es solo un detalle de la UI).
  ///
  /// El ID del registro se genera ANTES de escribirlo (necesario para
  /// nombrar la ruta de Storage de la foto/firma con ese mismo ID) — a
  /// diferencia de [registrarMovimiento], que deja que Firestore genere
  /// el ID en el mismo `set()`.
  Future<void> registrarSalidaEmergencia({
    required Registro salida,
    required Uint8List fotoBytes,
    required String fotoExt,
    required Uint8List firmaBytes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa.');
    }
    final docRef = _firestore.collection('registros').doc();

    String fotoUrl;
    String firmaUrl;
    try {
      final fotoRef = _storage.ref('emergencia_fotos/${docRef.id}/foto.$fotoExt');
      await fotoRef.putData(fotoBytes, _metadataDeFoto(fotoExt));
      fotoUrl = await fotoRef.getDownloadURL();

      final firmaRef = _storage.ref('emergencia_firmas/${docRef.id}/firma.png');
      await firmaRef.putData(
        firmaBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      firmaUrl = await firmaRef.getDownloadURL();
    } catch (e) {
      throw AuthException('No se pudo subir la foto/firma: $e');
    }

    final datos = salida.toFirestore()
      ..['fkIdServidor'] = user.uid
      ..['nombreServidor'] = salida.nombreServidor
      ..['modalidadRegistro'] = 'Emergencia'
      ..['fotoEntregaEmergenciaUrl'] = fotoUrl
      ..['firmaEntregaEmergenciaUrl'] = firmaUrl;

    final batch = _firestore.batch();
    batch.set(docRef, datos);
    if (salida.fkIdNino.isNotEmpty) {
      batch.update(_firestore.collection('ninos').doc(salida.fkIdNino), {
        'presente': false,
      });
    }
    try {
      await batch.commit();
    } catch (e) {
      throw AuthException('No se pudo registrar la salida de emergencia: $e');
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
    final acudienteDoc = await _firestore
        .collection('acudientes')
        .doc(uid)
        .get();
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
    final ninoDoc = await _firestore
        .collection('ninos')
        .doc(documentoNino)
        .get();
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
  /// Mismo fetch en paralelo que [obtenerMisHijos].
  Future<List<Nino>> obtenerHijosDeAcudiente(String acudienteUid) async {
    final relaciones = await _firestore
        .collection('nino_acudiente')
        .where('fk_idAcudiente', isEqualTo: acudienteUid)
        .get();

    final ninoIds = relaciones.docs
        .map((rel) => rel.data()['fk_idNino'] as String?)
        .whereType<String>()
        .toList();
    final ninoDocs = await Future.wait(
      ninoIds.map((id) => _firestore.collection('ninos').doc(id).get()),
    );
    return [
      for (final doc in ninoDocs)
        if (doc.exists) Nino.fromFirestore(doc.id, doc.data()!),
    ];
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
  /// identidad: sus relaciones con acudientes (`nino_acudiente`), su
  /// entrada en el índice de búsqueda (`ninos_busqueda`) y su lista de
  /// personas no autorizadas (`no_autorizados`). A propósito NO borra
  /// sus `registros` históricos de asistencia — quedan como dato
  /// histórico aunque el niño ya no exista. **Solo admin**.
  Future<void> eliminarNino(String documentoIdentificacion) async {
    final ninoRef = _firestore.collection('ninos').doc(documentoIdentificacion);
    final relaciones = await _firestore
        .collection('nino_acudiente')
        .where('fk_idNino', isEqualTo: documentoIdentificacion)
        .get();
    final noAutorizados = await ninoRef.collection('no_autorizados').get();
    final batch = _firestore.batch();
    for (final doc in noAutorizados.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in relaciones.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(
      _firestore.collection('ninos_busqueda').doc(documentoIdentificacion),
    );
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
      batch.delete(
        _firestore.collection('acudientes_documentos').doc(numeroDocumento),
      );
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
    DateTime? fechaNacimiento,
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
      'fechaNacimiento': fechaNacimiento != null
          ? Timestamp.fromDate(fechaNacimiento)
          : null,
      'mesDiaNacimiento': fechaNacimiento != null
          ? mesDiaDe(fechaNacimiento)
          : null,
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
    await ref.putData(bytes, _metadataDeFoto(extension));
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
    await ref.putData(bytes, _metadataDeFoto(extension));
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
    await ref.putData(bytes, _metadataDeFoto(extension));
    return ref.getDownloadURL();
  }

  /// Todos los videos tutoriales ("Video Tutoriales", 2026-08-22),
  /// ordenados del más nuevo al más viejo. Visible para cualquier cuenta
  /// logueada — el filtro por audiencia (acudientes/servidores/
  /// liderazgo) se aplica en la pantalla, no acá, para no necesitar un
  /// índice compuesto por cada combinación posible de `array-contains`.
  Stream<List<VideoTutorial>> listarVideosTutoriales() {
    return _firestore
        .collection('videos_tutoriales')
        .orderBy('creadoEn', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => VideoTutorial.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  /// Agrega un video tutorial nuevo. **Solo admin** (`firestore.rules`).
  /// El título ya viene resuelto desde YouTube (ver
  /// `utils/youtube_helper.dart`) — acá solo se guarda.
  Future<void> crearVideoTutorial({
    required String youtubeUrl,
    required String youtubeId,
    required String titulo,
    required String descripcion,
    required List<AudienciaManual> audiencias,
  }) async {
    await _firestore.collection('videos_tutoriales').add({
      ...VideoTutorial(
        id: '',
        youtubeUrl: youtubeUrl,
        youtubeId: youtubeId,
        titulo: titulo,
        descripcion: descripcion,
        audiencias: audiencias,
        creadoEn: DateTime.now(),
      ).toFirestore(),
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }

  /// Edita un video tutorial existente. **Solo admin**.
  Future<void> editarVideoTutorial({
    required String id,
    required String youtubeUrl,
    required String youtubeId,
    required String titulo,
    required String descripcion,
    required List<AudienciaManual> audiencias,
  }) async {
    await _firestore.collection('videos_tutoriales').doc(id).update(
      VideoTutorial(
        id: id,
        youtubeUrl: youtubeUrl,
        youtubeId: youtubeId,
        titulo: titulo,
        descripcion: descripcion,
        audiencias: audiencias,
        creadoEn: DateTime.now(),
      ).toFirestore(),
    );
  }

  /// **Solo admin**.
  Future<void> eliminarVideoTutorial(String id) async {
    await _firestore.collection('videos_tutoriales').doc(id).delete();
  }

  /// Todos los grupos de "Programación de Servidores" (2026-08-31,
  /// pedido de Rafael) — colección chica (unos 15-20 grupos entre las 4
  /// categorías), traerla completa es barato. Ordenado del lado del
  /// cliente por categoría (mismo orden que [categoriasProgramacion]) y
  /// nombre — un `orderBy` compuesto en Firestore exigiría un índice
  /// extra para algo que ordenar en memoria ya resuelve gratis.
  Stream<List<GrupoServidores>> listarGruposServidores() {
    return _firestore
        .collection('grupos_servidores')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => GrupoServidores.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  /// **Solo administrador o líder de ministerio**
  /// (`RolUsuario.puedeGestionarProgramacion`, ver `firestore.rules`).
  Future<void> crearGrupoServidores({
    required String categoria,
    required String nombre,
    required List<String> fkIdsServidores,
  }) async {
    await _firestore.collection('grupos_servidores').add({
      ...GrupoServidores(
        id: '',
        categoria: categoria,
        nombre: nombre,
        fkIdsServidores: fkIdsServidores,
        creadoEn: DateTime.now(),
      ).toFirestore(),
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }

  /// **Solo administrador o líder de ministerio**.
  Future<void> editarGrupoServidores({
    required String id,
    required String categoria,
    required String nombre,
    required List<String> fkIdsServidores,
  }) async {
    await _firestore.collection('grupos_servidores').doc(id).update(
      GrupoServidores(
        id: id,
        categoria: categoria,
        nombre: nombre,
        fkIdsServidores: fkIdsServidores,
        creadoEn: DateTime.now(),
      ).toFirestore(),
    );
  }

  /// **Solo administrador o líder de ministerio**.
  Future<void> eliminarGrupoServidores(String id) async {
    await _firestore.collection('grupos_servidores').doc(id).delete();
  }

  /// Sin esto, Storage guarda el archivo como `application/octet-stream`
  /// — Safari/iOS es estricto con el `Content-Type` real al decodificar
  /// una imagen y la muestra en blanco (encontrado 2026-08-19: fotos
  /// que sí cargaban en escritorio no cargaban en celular).
  SettableMetadata _metadataDeFoto(String extension) {
    final tipo = switch (extension.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    return SettableMetadata(contentType: tipo);
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

  String _mensajeDeErrorCodigoReset(String codigo) {
    switch (codigo) {
      case 'expired-action-code':
        return 'Este enlace ya venció. Solicita uno nuevo desde "¿Olvidaste tu contraseña?" en el login.';
      case 'invalid-action-code':
        return 'Este enlace ya se usó o no es válido. Solicita uno nuevo.';
      case 'user-disabled':
        return 'Esta cuenta está deshabilitada.';
      case 'user-not-found':
        return 'No se encontró la cuenta asociada a este enlace.';
      case 'weak-password':
        return 'La contraseña es muy débil (mínimo 6 caracteres).';
      default:
        return 'No se pudo completar el proceso. Intenta de nuevo.';
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

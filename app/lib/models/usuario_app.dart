import 'package:cloud_firestore/cloud_firestore.dart';

/// Los 7 roles del ministerio. Solo "administrador" tiene permisos
/// funcionales completos activados hoy; los demás quedan definidos para
/// que un admin ya pueda etiquetar correctamente a cada servidor, y se
/// les active acceso a pantallas propias en módulos futuros.
enum RolUsuario {
  administrador,
  liderMinisterio,
  columna,
  liderEscuelaSiervos,
  maestroPrincipal,
  maestroAuxiliar,
  usuarioExterno,
  pendiente,
  desconocido;

  static RolUsuario fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'administrador':
        return RolUsuario.administrador;
      case 'lider_ministerio':
        return RolUsuario.liderMinisterio;
      case 'columna':
        return RolUsuario.columna;
      case 'lider_escuela_siervos':
        return RolUsuario.liderEscuelaSiervos;
      case 'maestro_principal':
        return RolUsuario.maestroPrincipal;
      case 'maestro_auxiliar':
        return RolUsuario.maestroAuxiliar;
      case 'usuario_externo':
        return RolUsuario.usuarioExterno;
      case 'pendiente':
        return RolUsuario.pendiente;
      default:
        return RolUsuario.desconocido;
    }
  }

  /// Valor tal cual se guarda en Firestore (clave estable, no cambia
  /// aunque la etiqueta visible en la UI se traduzca o se ajuste).
  String get valorFirestore {
    switch (this) {
      case RolUsuario.administrador:
        return 'administrador';
      case RolUsuario.liderMinisterio:
        return 'lider_ministerio';
      case RolUsuario.columna:
        return 'columna';
      case RolUsuario.liderEscuelaSiervos:
        return 'lider_escuela_siervos';
      case RolUsuario.maestroPrincipal:
        return 'maestro_principal';
      case RolUsuario.maestroAuxiliar:
        return 'maestro_auxiliar';
      case RolUsuario.usuarioExterno:
        return 'usuario_externo';
      case RolUsuario.pendiente:
        return 'pendiente';
      case RolUsuario.desconocido:
        return 'desconocido';
    }
  }

  String get etiqueta {
    switch (this) {
      case RolUsuario.administrador:
        return 'Administrador';
      case RolUsuario.liderMinisterio:
        return 'Líder de Ministerio';
      case RolUsuario.columna:
        return 'Columna';
      case RolUsuario.liderEscuelaSiervos:
        return 'Líder Escuela de Siervos';
      case RolUsuario.maestroPrincipal:
        return 'Maestro Principal';
      case RolUsuario.maestroAuxiliar:
        return 'Maestro Auxiliar';
      case RolUsuario.usuarioExterno:
        return 'Usuario externo';
      case RolUsuario.pendiente:
        return 'Pendiente de aprobación';
      case RolUsuario.desconocido:
        return 'Sin rol asignado';
    }
  }

  /// Roles que un administrador puede asignar desde el panel.
  /// (excluye "pendiente" y "desconocido", que no son roles reales
  /// sino estados transitorios/de error)
  static List<RolUsuario> get asignables => RolUsuario.values
      .where((r) => r != RolUsuario.desconocido && r != RolUsuario.pendiente)
      .toList();

  /// Roles operativos del ministerio: una vez asignados, la persona debe
  /// completar su perfil de servidor (documento, EPS, contacto de
  /// emergencia, foto) antes de poder usar la app.
  bool get esRolDeServidor => this != RolUsuario.usuarioExterno &&
      this != RolUsuario.pendiente &&
      this != RolUsuario.desconocido;

  /// Quién puede ver el panel "Acudientes y Niños" (2026-08-17, pedido
  /// explícito de Rafael) — NO todos los roles principales, solo
  /// administrador, columna y líder de ministerio. Debe quedar
  /// sincronizado con `puedeVerListaAcudientes()` en firestore.rules.
  bool get puedeVerAcudientesYNinos =>
      this == RolUsuario.administrador ||
      this == RolUsuario.columna ||
      this == RolUsuario.liderMinisterio;
}

const gruposSanguineos = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

const tiposDocumento = [
  'Cédula de Ciudadanía',
  'Cédula de Extranjería',
  'Tarjeta de Identidad',
  'Pasaporte',
];

class UsuarioApp {
  final String uid;
  final String correo;
  final String nombre;
  final String apellido;
  final RolUsuario rol;
  final bool activo;

  // Perfil de servidor (SOP: tabla SERVIDORES). Se llenan por el propio
  // servidor la primera vez que entra con un rol ya asignado.
  final String tipoDocumento;
  final String numeroDocumento;
  final String telefono;
  final String epsNombre;
  final String grupoSanguineo;
  final String contactoEmergenciaNombre;
  final String contactoEmergenciaTelefono;
  final String fotoUrl;

  // Solo lo edita un administrador (verificación externa a la app).
  final DateTime? fechaVerificacionAntecedentes;

  const UsuarioApp({
    required this.uid,
    required this.correo,
    required this.nombre,
    required this.apellido,
    required this.rol,
    required this.activo,
    this.tipoDocumento = '',
    this.numeroDocumento = '',
    this.telefono = '',
    this.epsNombre = '',
    this.grupoSanguineo = '',
    this.contactoEmergenciaNombre = '',
    this.contactoEmergenciaTelefono = '',
    this.fotoUrl = '',
    this.fechaVerificacionAntecedentes,
  });

  String get nombreCompleto => [nombre, apellido].where((s) => s.isNotEmpty).join(' ');

  /// Todos los campos del perfil de servidor (no el rol/activo, que
  /// controla el admin) están llenos.
  bool get perfilCompleto =>
      tipoDocumento.isNotEmpty &&
      numeroDocumento.isNotEmpty &&
      telefono.isNotEmpty &&
      epsNombre.isNotEmpty &&
      grupoSanguineo.isNotEmpty &&
      contactoEmergenciaNombre.isNotEmpty &&
      contactoEmergenciaTelefono.isNotEmpty &&
      fotoUrl.isNotEmpty;

  factory UsuarioApp.fromFirestore(
    String uid,
    Map<String, dynamic> data,
  ) {
    final antecedentes = data['fechaVerificacionAntecedentes'];
    return UsuarioApp(
      uid: uid,
      correo: data['correo'] as String? ?? '',
      nombre: data['nombre'] as String? ?? '',
      apellido: data['apellido'] as String? ?? '',
      rol: RolUsuario.fromString(data['rol'] as String?),
      activo: data['activo'] as bool? ?? true,
      tipoDocumento: data['tipoDocumento'] as String? ?? '',
      numeroDocumento: data['numeroDocumento'] as String? ?? '',
      telefono: data['telefono'] as String? ?? '',
      epsNombre: data['epsNombre'] as String? ?? '',
      grupoSanguineo: data['grupoSanguineo'] as String? ?? '',
      contactoEmergenciaNombre: data['contactoEmergenciaNombre'] as String? ?? '',
      contactoEmergenciaTelefono: data['contactoEmergenciaTelefono'] as String? ?? '',
      fotoUrl: data['fotoUrl'] as String? ?? '',
      fechaVerificacionAntecedentes:
          antecedentes is Timestamp ? antecedentes.toDate() : null,
    );
  }
}

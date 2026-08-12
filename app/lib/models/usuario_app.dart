/// Roles soportados hoy. Se amplía en módulos futuros (Líder Ministerio,
/// Columna, Líder Escuela de Siervos, Maestro Principal/Auxiliar,
/// Usuario externo) sin tener que rediseñar el modelo.
enum RolUsuario {
  administrador,
  desconocido;

  static RolUsuario fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'administrador':
        return RolUsuario.administrador;
      default:
        return RolUsuario.desconocido;
    }
  }
}

class UsuarioApp {
  final String uid;
  final String correo;
  final String nombre;
  final RolUsuario rol;

  const UsuarioApp({
    required this.uid,
    required this.correo,
    required this.nombre,
    required this.rol,
  });

  factory UsuarioApp.fromFirestore(
    String uid,
    Map<String, dynamic> data,
  ) {
    return UsuarioApp(
      uid: uid,
      correo: data['correo'] as String? ?? '',
      nombre: data['nombre'] as String? ?? '',
      rol: RolUsuario.fromString(data['rol'] as String?),
    );
  }
}

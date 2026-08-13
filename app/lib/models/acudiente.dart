const tiposDocumentoAcudiente = [
  'Cédula de Ciudadanía',
  'Cédula de Extranjería',
  'Pasaporte',
];

class Acudiente {
  final String uid;
  final String tipoDocumento;
  final String numeroDocumento;
  final String nombres;
  final String apellidos;
  final String telefonoCelular;
  final String correoElectronico;
  final String fotoSeguridadUrl;
  final String estadoAutorizacion; // Autorizado | Restringido — solo lo cambia un admin
  final String observacionesRestriccion;

  const Acudiente({
    required this.uid,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.nombres,
    required this.apellidos,
    required this.telefonoCelular,
    required this.correoElectronico,
    this.fotoSeguridadUrl = '',
    this.estadoAutorizacion = 'Autorizado',
    this.observacionesRestriccion = '',
  });

  String get nombreCompleto => '$nombres $apellidos';

  Map<String, dynamic> toFirestore() => {
    'tipoDocumento': tipoDocumento,
    'numeroDocumento': numeroDocumento,
    'nombres': nombres,
    'apellidos': apellidos,
    'telefonoCelular': telefonoCelular,
    'correoElectronico': correoElectronico,
    'fotoSeguridadUrl': fotoSeguridadUrl,
    'estadoAutorizacion': estadoAutorizacion,
    'observacionesRestriccion': observacionesRestriccion,
  };

  factory Acudiente.fromFirestore(String uid, Map<String, dynamic> data) {
    return Acudiente(
      uid: uid,
      tipoDocumento: data['tipoDocumento'] as String? ?? '',
      numeroDocumento: data['numeroDocumento'] as String? ?? '',
      nombres: data['nombres'] as String? ?? '',
      apellidos: data['apellidos'] as String? ?? '',
      telefonoCelular: data['telefonoCelular'] as String? ?? '',
      correoElectronico: data['correoElectronico'] as String? ?? '',
      fotoSeguridadUrl: data['fotoSeguridadUrl'] as String? ?? '',
      estadoAutorizacion: data['estadoAutorizacion'] as String? ?? 'Autorizado',
      observacionesRestriccion: data['observacionesRestriccion'] as String? ?? '',
    );
  }
}

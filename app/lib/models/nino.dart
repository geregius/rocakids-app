import 'package:cloud_firestore/cloud_firestore.dart';

const tiposIdentificacionMenor = [
  'Registro Civil',
  'Tarjeta de Identidad',
  'Cédula de Extranjería',
  'Pasaporte',
  'No tiene documento',
];

const generos = ['Masculino', 'Femenino'];

const parentescos = [
  'Padre',
  'Madre',
  'Tío/a',
  'Abuelo/a',
  'Acudiente Autorizado',
];

/// Genera la llave interna del SOP (§3.2) cuando el menor no tiene
/// número de documento: fechaNacimiento-PRIMERNOMBRE-PRIMERAPELLIDO.
String generarLlaveInterna({
  required DateTime fechaNacimiento,
  required String nombres,
  required String apellidos,
}) {
  final fecha =
      '${fechaNacimiento.year.toString().padLeft(4, '0')}'
      '${fechaNacimiento.month.toString().padLeft(2, '0')}'
      '${fechaNacimiento.day.toString().padLeft(2, '0')}';
  final primerNombre = nombres.trim().split(RegExp(r'\s+')).first.toUpperCase();
  final primerApellido = apellidos.trim().split(RegExp(r'\s+')).first.toUpperCase();
  return '$fecha-$primerNombre-$primerApellido';
}

class Nino {
  final String documentoIdentificacion; // ID del documento en Firestore
  final String tipoIdentificacion;
  final String identificacionMenor;
  final String nombres;
  final String apellidos;
  final DateTime fechaNacimiento;
  final String genero;
  final String estadoRegistro;
  final bool alertaMedicaFlag;
  final String condicionMedica;
  final bool autorizoFotoFlag;
  final String fotoUrl;

  const Nino({
    required this.documentoIdentificacion,
    required this.tipoIdentificacion,
    required this.identificacionMenor,
    required this.nombres,
    required this.apellidos,
    required this.fechaNacimiento,
    required this.genero,
    required this.estadoRegistro,
    required this.alertaMedicaFlag,
    required this.condicionMedica,
    required this.autorizoFotoFlag,
    this.fotoUrl = '',
  });

  String get nombreCompleto => '$nombres $apellidos';

  Map<String, dynamic> toFirestore() => {
    'documentoIdentificacion': documentoIdentificacion,
    'tipoIdentificacion': tipoIdentificacion,
    'identificacionMenor': identificacionMenor,
    'nombres': nombres,
    'apellidos': apellidos,
    'fechaNacimiento': Timestamp.fromDate(fechaNacimiento),
    'genero': genero,
    'estadoRegistro': estadoRegistro,
    'alertaMedicaFlag': alertaMedicaFlag,
    'condicionMedica': condicionMedica,
    'autorizoFotoFlag': autorizoFotoFlag,
    'fotoUrl': fotoUrl,
  };

  factory Nino.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['fechaNacimiento'];
    return Nino(
      documentoIdentificacion: id,
      tipoIdentificacion: data['tipoIdentificacion'] as String? ?? '',
      identificacionMenor: data['identificacionMenor'] as String? ?? '',
      nombres: data['nombres'] as String? ?? '',
      apellidos: data['apellidos'] as String? ?? '',
      fechaNacimiento: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
      genero: data['genero'] as String? ?? '',
      estadoRegistro: data['estadoRegistro'] as String? ?? '',
      alertaMedicaFlag: data['alertaMedicaFlag'] as bool? ?? false,
      condicionMedica: data['condicionMedica'] as String? ?? '',
      autorizoFotoFlag: data['autorizoFotoFlag'] as bool? ?? false,
      fotoUrl: data['fotoUrl'] as String? ?? '',
    );
  }
}

class NinoAcudiente {
  final String id;
  final String fkIdNino;
  final String fkIdAcudiente;
  final String parentescoTipo;
  final String autorizacionFormulario;
  final String autorizacionImagen;
  final bool esRepresentanteLegalFlag;

  const NinoAcudiente({
    required this.id,
    required this.fkIdNino,
    required this.fkIdAcudiente,
    required this.parentescoTipo,
    required this.autorizacionFormulario,
    required this.autorizacionImagen,
    required this.esRepresentanteLegalFlag,
  });

  Map<String, dynamic> toFirestore() => {
    'fk_idNino': fkIdNino,
    'fk_idAcudiente': fkIdAcudiente,
    'parentescoTipo': parentescoTipo,
    'autorizacionFormulario': autorizacionFormulario,
    'autorizacionImagen': autorizacionImagen,
    'esRepresentanteLegalFlag': esRepresentanteLegalFlag,
  };

  factory NinoAcudiente.fromFirestore(String id, Map<String, dynamic> data) {
    return NinoAcudiente(
      id: id,
      fkIdNino: data['fk_idNino'] as String? ?? '',
      fkIdAcudiente: data['fk_idAcudiente'] as String? ?? '',
      parentescoTipo: data['parentescoTipo'] as String? ?? '',
      autorizacionFormulario: data['autorizacionFormulario'] as String? ?? '',
      autorizacionImagen: data['autorizacionImagen'] as String? ?? '',
      esRepresentanteLegalFlag: data['esRepresentanteLegalFlag'] as bool? ?? false,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicios/cultos donde se registra asistencia infantil. Lista fija
/// tomada de los valores reales usados en la base de datos histórica de
/// RocaKids (AppSheet) — si cambian los servicios de la iglesia, este es
/// el único lugar que hay que actualizar.
const serviciosDisponibles = [
  'Domingo 1° Servicio',
  'Domingo 2° Servicio',
  'Miércoles',
  'Ayuno',
  'Casa2',
];

const tiposMovimiento = ['Entrada', 'Salida'];

/// Un movimiento de entrada o salida de un niño (SOP §2.4, tabla
/// REGISTROS). Puede ser de un niño YA registrado (`fkIdNino` con valor)
/// o de un niño VISITANTE que llega por primera vez sin cuenta previa
/// (`fkIdNino` vacío, se guardan sus datos sueltos en los campos
/// `*Visitante`) — para no rechazar a nadie en la puerta.
class Registro {
  final String id;
  final String fkIdNino; // vacío si es visitante
  final String nombreNinoVisitante;
  final String tipoMovimiento; // Entrada | Salida
  final DateTime fechaMovimiento;
  final String numeroManilla;
  final String fkIdServidor; // uid de quien registra
  final String nombreServidor;
  final String
  fkIdAcudienteContacto; // uid del acudiente, vacío si "otro"/visitante
  final String nombreAcudienteContacto;
  final String tipoIdentificacionVisitante;
  final String documentoNinoVisitante;
  final String telefonoAcudienteVisitante;
  final bool alertaMedicaVisitante;
  final String condicionMedicaVisitante;
  final String modalidadRegistro;
  final String servicio;
  final String grupoEdad;
  final String observacion;

  const Registro({
    required this.id,
    this.fkIdNino = '',
    this.nombreNinoVisitante = '',
    required this.tipoMovimiento,
    required this.fechaMovimiento,
    required this.numeroManilla,
    required this.fkIdServidor,
    required this.nombreServidor,
    this.fkIdAcudienteContacto = '',
    required this.nombreAcudienteContacto,
    this.tipoIdentificacionVisitante = '',
    this.documentoNinoVisitante = '',
    this.telefonoAcudienteVisitante = '',
    this.alertaMedicaVisitante = false,
    this.condicionMedicaVisitante = '',
    this.modalidadRegistro = 'App',
    required this.servicio,
    this.grupoEdad = '',
    this.observacion = '',
  });

  bool get esVisitante => fkIdNino.isEmpty;

  String get nombreNino => nombreNinoVisitante;

  Map<String, dynamic> toFirestore() => {
    'fkIdNino': fkIdNino,
    'nombreNinoVisitante': nombreNinoVisitante,
    'tipoMovimiento': tipoMovimiento,
    'fechaMovimiento': Timestamp.fromDate(fechaMovimiento),
    'numeroManilla': numeroManilla,
    'fkIdServidor': fkIdServidor,
    'nombreServidor': nombreServidor,
    'fkIdAcudienteContacto': fkIdAcudienteContacto,
    'nombreAcudienteContacto': nombreAcudienteContacto,
    'tipoIdentificacionVisitante': tipoIdentificacionVisitante,
    'documentoNinoVisitante': documentoNinoVisitante,
    'telefonoAcudienteVisitante': telefonoAcudienteVisitante,
    'alertaMedicaVisitante': alertaMedicaVisitante,
    'condicionMedicaVisitante': condicionMedicaVisitante,
    'modalidadRegistro': modalidadRegistro,
    'servicio': servicio,
    'grupoEdad': grupoEdad,
    'observacion': observacion,
  };

  factory Registro.fromFirestore(String id, Map<String, dynamic> data) {
    final fecha = data['fechaMovimiento'];
    return Registro(
      id: id,
      fkIdNino: data['fkIdNino'] as String? ?? '',
      nombreNinoVisitante: data['nombreNinoVisitante'] as String? ?? '',
      tipoMovimiento: data['tipoMovimiento'] as String? ?? '',
      fechaMovimiento: fecha is Timestamp ? fecha.toDate() : DateTime.now(),
      numeroManilla: data['numeroManilla'] as String? ?? '',
      fkIdServidor: data['fkIdServidor'] as String? ?? '',
      nombreServidor: data['nombreServidor'] as String? ?? '',
      fkIdAcudienteContacto: data['fkIdAcudienteContacto'] as String? ?? '',
      nombreAcudienteContacto: data['nombreAcudienteContacto'] as String? ?? '',
      tipoIdentificacionVisitante:
          data['tipoIdentificacionVisitante'] as String? ?? '',
      documentoNinoVisitante: data['documentoNinoVisitante'] as String? ?? '',
      telefonoAcudienteVisitante:
          data['telefonoAcudienteVisitante'] as String? ?? '',
      alertaMedicaVisitante: data['alertaMedicaVisitante'] as bool? ?? false,
      condicionMedicaVisitante:
          data['condicionMedicaVisitante'] as String? ?? '',
      modalidadRegistro: data['modalidadRegistro'] as String? ?? '',
      servicio: data['servicio'] as String? ?? '',
      grupoEdad: data['grupoEdad'] as String? ?? '',
      observacion: data['observacion'] as String? ?? '',
    );
  }
}

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

/// El servicio que corresponde AHORA según el día/hora de hoy, para
/// pre-seleccionarlo en el formulario de registro (el servidor lo puede
/// cambiar igual si hace falta) — pedido de Rafael, 2026-08-15. `null`
/// si hoy no hay ningún servicio (lunes, martes, jueves).
String? servicioSugerido([DateTime? ahora]) {
  final hoy = ahora ?? DateTime.now();
  switch (hoy.weekday) {
    case DateTime.wednesday:
      return 'Miércoles';
    case DateTime.friday:
      return 'Casa2';
    case DateTime.saturday:
      return 'Ayuno';
    case DateTime.sunday:
      return hoy.hour < 10 ? 'Domingo 1° Servicio' : 'Domingo 2° Servicio';
    default:
      return null;
  }
}

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
  // Solo se llenan en una Salida de "Modo emergencia" (2026-08-19, ver
  // modo_emergencia_screen.dart): evidencia extra de quién retiró al
  // niño, exigida además del acudiente elegido/escrito de siempre.
  final String fotoEntregaEmergenciaUrl;
  final String firmaEntregaEmergenciaUrl;
  // Copia del `nombreAcudienteContacto` de la Entrada correspondiente,
  // tomada en el momento de la Salida de emergencia — para que el
  // reporte pueda mostrar "según RocaKids lo entregó X" vs. "en la
  // emergencia lo retiró Y" sin tener que volver a cruzar registros.
  final String nombreAcudienteEntradaOriginal;

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
    this.fotoEntregaEmergenciaUrl = '',
    this.firmaEntregaEmergenciaUrl = '',
    this.nombreAcudienteEntradaOriginal = '',
  });

  bool get esVisitante => fkIdNino.isEmpty;
  bool get esEmergencia => modalidadRegistro == 'Emergencia';

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
    'fotoEntregaEmergenciaUrl': fotoEntregaEmergenciaUrl,
    'firmaEntregaEmergenciaUrl': firmaEntregaEmergenciaUrl,
    'nombreAcudienteEntradaOriginal': nombreAcudienteEntradaOriginal,
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
      fotoEntregaEmergenciaUrl: data['fotoEntregaEmergenciaUrl'] as String? ?? '',
      firmaEntregaEmergenciaUrl:
          data['firmaEntregaEmergenciaUrl'] as String? ?? '',
      nombreAcudienteEntradaOriginal:
          data['nombreAcudienteEntradaOriginal'] as String? ?? '',
    );
  }
}

/// De todos los movimientos de un día, deja solo a quien está presente
/// AHORA: para un niño registrado, su movimiento más reciente debe ser
/// "Entrada" (si ya salió, no cuenta); para un visitante, cada "Entrada"
/// cuenta por separado (no hay forma de dar salida a un visitante desde
/// el registro manual, así que cada una es una presencia distinta).
/// Compartido entre "Menores Recibidos" y "Modo emergencia" (2026-08-19)
/// — antes vivía solo en `ninos_presentes_screen.dart`; se movió acá
/// para que ambas pantallas usen EXACTAMENTE el mismo criterio de
/// "quién está presente", crítico para que el listado de una emergencia
/// no pueda quedar desincronizado del real.
List<Registro> calcularPresentes(List<Registro> registrosDelDia) {
  final ultimoPorNino = <String, Registro>{};
  final visitantesPresentes = <Registro>[];
  for (final r in registrosDelDia) {
    if (r.esVisitante) {
      if (r.tipoMovimiento == 'Entrada') visitantesPresentes.add(r);
      continue;
    }
    // Los registros ya vienen ordenados por fecha ascendente, así que
    // el último que se procese por niño es el más reciente.
    ultimoPorNino[r.fkIdNino] = r;
  }
  return [
    ...ultimoPorNino.values.where((r) => r.tipoMovimiento == 'Entrada'),
    ...visitantesPresentes,
  ];
}

/// Un mes de `resumenes_mensuales/{AAAA-MM}` — totales de Entradas ya
/// agregados, mantenidos por la Cloud Function `actualizarResumenMensual`
/// (2026-08-19). Reemplaza traer TODOS los `Registro` crudos para el
/// bloque "Histórico" del Dashboard: en vez de miles de documentos, es
/// un puñado de resúmenes (uno por mes transcurrido desde que existe la
/// app).
class ResumenMensual {
  /// Primer día del mes que representa este resumen (ej. `2026-08-01`
  /// para el ID de documento `"2026-08"`).
  final DateTime mes;
  final int totalEntradas;
  final int ninosNuevos;
  final Map<String, int> porServicio;

  const ResumenMensual({
    required this.mes,
    required this.totalEntradas,
    required this.ninosNuevos,
    required this.porServicio,
  });

  factory ResumenMensual.fromFirestore(String id, Map<String, dynamic> data) {
    final partes = id.split('-');
    final mes = DateTime(int.parse(partes[0]), int.parse(partes[1]), 1);
    final porServicio = <String, int>{};
    final rawPorServicio = data['porServicio'];
    if (rawPorServicio is Map) {
      for (final entry in rawPorServicio.entries) {
        porServicio[entry.key as String] = (entry.value as num).toInt();
      }
    }
    return ResumenMensual(
      mes: mes,
      totalEntradas: (data['totalEntradas'] as num?)?.toInt() ?? 0,
      ninosNuevos: (data['ninosNuevos'] as num?)?.toInt() ?? 0,
      porServicio: porServicio,
    );
  }
}

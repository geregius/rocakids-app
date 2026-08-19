import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/registro.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/escaner_qr.dart';
import '../widgets/app_shell.dart';
import 'nino_detalle_sheet.dart';

const _sinGrupo = 'Sin grupo';

/// Sección "Menores Recibidos", para los roles principales (ver
/// `usuario.rol.esRolDeServidor`): quiénes están AHORA MISMO en el
/// salón (no todos los que pasaron hoy), subdivididos por grupo de
/// edad, cada grupo con su total. Una vista histórica del día completo
/// (incluyendo quien ya salió) queda pendiente para más adelante —
/// decisión explícita de Rafael, 2026-08-15.
///
/// "Presente" = el último movimiento de HOY de ese niño fue "Entrada".
/// Los niños VISITANTES (sin cuenta previa) se cuentan también: como
/// esta fase de la app no tiene forma de registrar la salida de un
/// visitante (`registrar_asistencia_screen.dart` solo permite su
/// Entrada), CADA entrada de visitante de hoy cuenta como presente —
/// es una limitación conocida de esta fase, no un bug de esta pantalla.
///
/// Deslizar la tarjeta de un niño (a cualquier lado) le da la SALIDA de
/// inmediato — sin confirmación ni volver a preguntar quién lo retira,
/// pedido explícito de Rafael: se asume que se lo entrega la MISMA
/// persona que quedó registrada en su entrada (`fkIdAcudienteContacto`/
/// `nombreAcudienteContacto`, copiados tal cual al nuevo registro de
/// Salida). Un cierre automático nocturno (Cloud Function,
/// `functions/index.js`) cubre a quien se quede sin salida manual.
class NinosPresentesScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const NinosPresentesScreen({super.key, required this.usuario});

  @override
  State<NinosPresentesScreen> createState() => _NinosPresentesScreenState();
}

class _NinosPresentesScreenState extends State<NinosPresentesScreen> {
  final _authService = AuthService();
  bool _cargandoNinos = true;
  Map<String, Nino> _ninosPorId = {};

  // IDs de registros de ENTRADA a los que ya se les dio salida desde esta
  // pantalla, pero el stream de Firestore todavía no lo refleja (hay un
  // pequeño retraso de red). Se ocultan de inmediato en el cliente para
  // que el swipe se sienta instantáneo; el propio ID nuevo de cada
  // entrada futura nunca choca con uno viejo, así que no hace falta
  // limpiar este set.
  final Set<String> _ocultosOptimista = {};

  @override
  void initState() {
    super.initState();
    _cargarNinos();
  }

  Future<void> _cargarNinos() async {
    try {
      final ninos = await _authService.obtenerTodosLosNinos();
      if (mounted) {
        setState(() {
          _ninosPorId = {for (final n in ninos) n.documentoIdentificacion: n};
          _cargandoNinos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoNinos = false);
    }
  }

  /// De todos los movimientos de hoy, deja solo a quien está presente
  /// ahora: para un niño registrado, su movimiento más reciente debe ser
  /// "Entrada" (si ya salió, no cuenta); para un visitante, cada
  /// "Entrada" cuenta por separado (ver docstring de la clase).
  List<Registro> _calcularPresentes(List<Registro> registrosDeHoy) {
    final ultimoPorNino = <String, Registro>{};
    final visitantesPresentes = <Registro>[];
    for (final r in registrosDeHoy) {
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
    ].where((r) => !_ocultosOptimista.contains(r.id)).toList();
  }

  /// Registra la salida de `entrada` con la fecha/hora actual, copiando
  /// quién lo retira desde su propia entrada (mismo criterio que pidió
  /// Rafael: "solo se entrega a la misma persona que lo recibió"). Usa
  /// [observacion] para distinguir cómo se disparó (deslizar la tarjeta
  /// o escanear la manilla, 2026-08-18).
  Future<void> _darSalida(
    Registro entrada, {
    String observacion = 'Salida registrada deslizando la tarjeta en Menores Recibidos.',
  }) async {
    setState(() => _ocultosOptimista.add(entrada.id));
    final salida = Registro(
      id: '',
      fkIdNino: entrada.fkIdNino,
      nombreNinoVisitante: entrada.nombreNinoVisitante,
      tipoMovimiento: 'Salida',
      fechaMovimiento: DateTime.now(),
      numeroManilla: entrada.numeroManilla,
      fkIdServidor: '',
      nombreServidor: widget.usuario.nombreCompleto,
      fkIdAcudienteContacto: entrada.fkIdAcudienteContacto,
      nombreAcudienteContacto: entrada.nombreAcudienteContacto,
      tipoIdentificacionVisitante: entrada.tipoIdentificacionVisitante,
      documentoNinoVisitante: entrada.documentoNinoVisitante,
      telefonoAcudienteVisitante: entrada.telefonoAcudienteVisitante,
      alertaMedicaVisitante: entrada.alertaMedicaVisitante,
      condicionMedicaVisitante: entrada.condicionMedicaVisitante,
      servicio: entrada.servicio,
      grupoEdad: entrada.grupoEdad,
      observacion: observacion,
    );
    try {
      await _authService.registrarMovimiento(salida);
    } catch (e) {
      if (mounted) {
        setState(() => _ocultosOptimista.remove(entrada.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo registrar la salida: $e')),
        );
      }
    }
  }

  /// Escanea la manilla gemela del acudiente y da salida al instante al
  /// niño que tenga esa manilla puesta ahora mismo (2026-08-18, pedido
  /// de Rafael) — alternativa al deslizar la tarjeta, para cuando ya
  /// haya manillas físicas con QR. Muestra al niño antes de confirmar,
  /// para verificar de un vistazo que es el correcto.
  Future<void> _escanearYDarSalida() async {
    final codigo = await escanearCodigoManilla(context);
    if (codigo == null || codigo.isEmpty || !mounted) return;

    final Registro? registro;
    try {
      registro = await _authService.buscarPresentePorManilla(codigo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo buscar la manilla: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    if (registro == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró ningún niño presente con esa manilla.'),
        ),
      );
      return;
    }

    final nino = registro.esVisitante ? null : _ninosPorId[registro.fkIdNino];
    final nombre = registro.esVisitante
        ? registro.nombreNinoVisitante
        : (nino?.nombreCompleto ?? '(sin datos)');
    final fotoUrl = nino?.fotoUrl ?? '';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Dar salida a este niño?'),
        content: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.amarillo,
              backgroundImage: fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
              child: fotoUrl.isEmpty
                  ? const Icon(Icons.child_care, color: AppColors.textoPrincipal)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(nombre, style: const TextStyle(fontSize: 16))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar salida'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _darSalida(
        registro,
        observacion: 'Salida registrada escaneando la manilla en Menores Recibidos.',
      );
    }
  }

  Map<String, List<Registro>> _agruparPorEdad(List<Registro> presentes) {
    final grupos = <String, List<Registro>>{};
    for (final r in presentes) {
      final grupo = gruposEdad.contains(r.grupoEdad) ? r.grupoEdad : _sinGrupo;
      grupos.putIfAbsent(grupo, () => []).add(r);
    }
    for (final lista in grupos.values) {
      lista.sort(
        (a, b) => _nombreDe(a).toLowerCase().compareTo(_nombreDe(b).toLowerCase()),
      );
    }
    return grupos;
  }

  String _nombreDe(Registro r) =>
      r.esVisitante ? r.nombreNinoVisitante : (_ninosPorId[r.fkIdNino]?.nombreCompleto ?? '(sin datos)');

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Menores Recibidos',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _escanearYDarSalida,
        icon: const Icon(Icons.photo_camera),
        label: const Text('Salida por manilla'),
      ),
      body: _cargandoNinos
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Registro>>(
              stream: _authService.registrosDeHoy(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final presentes = _calcularPresentes(snapshot.data ?? []);
                final grupos = _agruparPorEdad(presentes);
                final ordenados = [
                  ...gruposEdad,
                  if (grupos.containsKey(_sinGrupo)) _sinGrupo,
                ];

                if (presentes.isEmpty) {
                  return const Center(
                    child: Text('No hay niños presentes en este momento.'),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Total presentes: ${presentes.length}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    for (final grupo in ordenados)
                      if (grupos[grupo] != null)
                        _GrupoSection(
                          key: ValueKey(grupo),
                          nombre: grupo,
                          registros: grupos[grupo]!,
                          ninosPorId: _ninosPorId,
                          usuario: widget.usuario,
                          onDarSalida: _darSalida,
                        ),
                  ],
                );
              },
            ),
    );
  }
}

class _GrupoSection extends StatelessWidget {
  final String nombre;
  final List<Registro> registros;
  final Map<String, Nino> ninosPorId;
  final UsuarioApp usuario;
  final ValueChanged<Registro> onDarSalida;

  const _GrupoSection({
    super.key,
    required this.nombre,
    required this.registros,
    required this.ninosPorId,
    required this.usuario,
    required this.onDarSalida,
  });

  @override
  Widget build(BuildContext context) {
    final rangoEdad = rangoEdadPorGrupo[nombre];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              rangoEdad != null
                  ? 'Grupo $nombre · $rangoEdad (${registros.length})'
                  : 'Grupo $nombre (${registros.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.azulMarino,
                fontWeight: FontWeight.bold,
              ),
            ),
            children: [
              const Divider(height: 1),
              for (final r in registros)
                _NinoPresenteTile(
                  registro: r,
                  ninosPorId: ninosPorId,
                  usuario: usuario,
                  onDarSalida: onDarSalida,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NinoPresenteTile extends StatelessWidget {
  final Registro registro;
  final Map<String, Nino> ninosPorId;
  final UsuarioApp usuario;
  final ValueChanged<Registro> onDarSalida;

  const _NinoPresenteTile({
    required this.registro,
    required this.ninosPorId,
    required this.usuario,
    required this.onDarSalida,
  });

  void _abrirFicha(BuildContext context) {
    final nino = registro.esVisitante ? null : ninosPorId[registro.fkIdNino];
    if (nino != null) {
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => NinoDetalleSheet(nino: nino, usuario: usuario),
      );
    } else if (registro.esVisitante) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _VisitanteDetalleSheet(registro: registro),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nino = registro.esVisitante ? null : ninosPorId[registro.fkIdNino];
    final nombre = registro.esVisitante
        ? registro.nombreNinoVisitante
        : (nino?.nombreCompleto ?? '(sin datos)');
    final tieneAlertaMedica =
        registro.esVisitante ? registro.alertaMedicaVisitante : (nino?.alertaMedicaFlag ?? false);
    final fotoUrl = nino?.fotoUrl ?? '';
    final documento = registro.esVisitante
        ? registro.documentoNinoVisitante
        : (nino?.identificacionMenor ?? '');
    final documentoTexto = documento.isNotEmpty ? documento : 'Sin documento';

    return Dismissible(
      key: ValueKey(registro.id),
      direction: DismissDirection.horizontal,
      background: _fondoSalida(Alignment.centerLeft),
      secondaryBackground: _fondoSalida(Alignment.centerRight),
      onDismissed: (_) => onDarSalida(registro),
      child: ListTile(
        onTap: () => _abrirFicha(context),
        leading: CircleAvatar(
          backgroundColor: AppColors.amarillo,
          backgroundImage: fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
          child: fotoUrl.isEmpty
              ? const Icon(Icons.child_care, color: AppColors.textoPrincipal)
              : null,
        ),
        title: Text(nombre),
        subtitle: Text('$documentoTexto · Manilla ${registro.numeroManilla}'),
        trailing: tieneAlertaMedica
            ? const Tooltip(
                message: 'Tiene condición médica/alergia registrada',
                child: Icon(Icons.medical_information, color: AppColors.rojo),
              )
            : null,
      ),
    );
  }

  Widget _fondoSalida(Alignment alignment) {
    return Container(
      color: AppColors.rojo,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.logout, color: Colors.white),
          SizedBox(width: 8),
          Text('Salida', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Ficha mínima de un niño VISITANTE (no tiene documento `Nino` en la
/// base — sus datos viven solo en el `Registro` de su entrada de hoy).
class _VisitanteDetalleSheet extends StatelessWidget {
  final Registro registro;
  const _VisitanteDetalleSheet({required this.registro});

  @override
  Widget build(BuildContext context) {
    final hora = registro.fechaMovimiento;
    final horaTexto =
        '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.amarillo,
                child: Icon(Icons.child_care, color: AppColors.textoPrincipal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      registro.nombreNinoVisitante,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Visitante · Grupo ${registro.grupoEdad}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FilaDato(
            'Documento',
            '${registro.tipoIdentificacionVisitante}: '
                '${registro.documentoNinoVisitante.isNotEmpty ? registro.documentoNinoVisitante : 'Sin documento'}',
          ),
          _FilaDato('Manilla', registro.numeroManilla),
          _FilaDato('Entró a las', horaTexto),
          _FilaDato('Adulto que lo trajo', registro.nombreAcudienteContacto),
          if (registro.telefonoAcudienteVisitante.isNotEmpty)
            _FilaDato('Teléfono', registro.telefonoAcudienteVisitante),
          if (registro.alertaMedicaVisitante) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rojo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.medical_information, color: AppColors.rojo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      registro.condicionMedicaVisitante.isNotEmpty
                          ? registro.condicionMedicaVisitante
                          : 'Tiene una condición médica/alergia registrada.',
                      style: const TextStyle(color: AppColors.rojo),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _FilaDato(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}

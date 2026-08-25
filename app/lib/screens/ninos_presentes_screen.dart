import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/registro.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/escaner_qr.dart';
import '../utils/llamar_telefono.dart';
import '../widgets/app_shell.dart';
import '../widgets/foto_avatar.dart';
import 'nino_detalle_sheet.dart';
import 'registro_asistencia_screen.dart';

// "Sin grupo" hasta 2026-08-24. En la práctica SIEMPRE significa
// "mayor de 11 años" (`grupoParaEdad()` devuelve null a partir de esa
// edad) — nunca "menor de 2": el selector de fecha de nacimiento no
// deja registrar a nadie por debajo del mínimo (`edadMinimaRegistro`),
// así que un niño activo en el sistema no puede tener menos de 2 años.
// Pedido de Rafael: renombrarlo para que sea explícito.
const _sinGrupo = 'Mayores de 11 años';

/// Sección "Menores Registrados" (nombre hasta 2026-08-24: "Menores
/// Recibidos" — Rafael pidió unirla con "Registro de asistencia", que
/// dejó de ser un ítem de menú aparte y ahora se abre con el botón "+"
/// de acá, apilado encima con `Navigator.push`. Es la MISMA pantalla
/// sin ningún cambio interno, así que no hay ningún costo de
/// rendimiento nuevo — antes se llegaba desde el menú, ahora desde este
/// botón), para los roles principales (ver `usuario.rol.esRolDeServidor`):
/// quiénes están AHORA MISMO en el salón (no todos los que pasaron hoy),
/// subdivididos por grupo de edad, cada grupo con su total. Una vista
/// histórica del día completo (incluyendo quien ya salió) queda
/// pendiente para más adelante — decisión explícita de Rafael, 2026-08-15.
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

  // Antes se traían los ~460 niños completos (`obtenerTodosLosNinos()`)
  // antes de mostrar nada — lento en celular, y de sobra: "presentes
  // ahora" normalmente son unos pocos. Ahora se pide bajo demanda, solo
  // los niños que de verdad aparecen en el stream de hoy (2026-08-19).
  // `_ninosPorId` se va llenando incrementalmente y nunca se limpia
  // (una vez cargado un niño, sirve para toda la sesión); `_pidiendo`
  // evita pedir dos veces al mismo niño si el stream se actualiza antes
  // de que termine la consulta anterior.
  final Map<String, Nino> _ninosPorId = {};
  final Set<String> _pidiendo = {};

  // IDs de registros de ENTRADA a los que ya se les dio salida desde esta
  // pantalla, pero el stream de Firestore todavía no lo refleja (hay un
  // pequeño retraso de red). Se ocultan de inmediato en el cliente para
  // que el swipe se sienta instantáneo; el propio ID nuevo de cada
  // entrada futura nunca choca con uno viejo, así que no hace falta
  // limpiar este set.
  final Set<String> _ocultosOptimista = {};

  void _asegurarNinosCargados(Iterable<String> ids) {
    final faltantes = ids
        .where((id) => !_ninosPorId.containsKey(id) && !_pidiendo.contains(id))
        .toSet();
    if (faltantes.isEmpty) return;
    _pidiendo.addAll(faltantes);
    _authService.obtenerNinosPorIds(faltantes).then((ninos) {
      if (!mounted) return;
      setState(() {
        for (final n in ninos) {
          _ninosPorId[n.documentoIdentificacion] = n;
        }
        _pidiendo.removeAll(faltantes);
      });
    });
  }

  /// Envuelve la función compartida [calcularPresentes] (`models/registro.dart`)
  /// agregando el ocultamiento optimista propio de esta pantalla (ver
  /// `_ocultosOptimista` arriba).
  List<Registro> _calcularPresentes(List<Registro> registrosDeHoy) {
    return calcularPresentes(
      registrosDeHoy,
    ).where((r) => !_ocultosOptimista.contains(r.id)).toList();
  }

  /// Registra la salida de `entrada` con la fecha/hora actual, copiando
  /// quién lo retira desde su propia entrada (mismo criterio que pidió
  /// Rafael: "solo se entrega a la misma persona que lo recibió"). Usa
  /// [observacion] para distinguir cómo se disparó (deslizar la tarjeta
  /// o escanear la manilla, 2026-08-18).
  Future<void> _darSalida(
    Registro entrada, {
    String observacion = 'Salida registrada deslizando la tarjeta en Menores Registrados.',
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
            FotoAvatar(
              url: fotoUrl,
              radius: 28,
              iconoSinFoto: Icons.child_care,
              backgroundColor: AppColors.amarillo,
              iconColor: AppColors.textoPrincipal,
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
        observacion: 'Salida registrada escaneando la manilla en Menores Registrados.',
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
      seccionActiva: 'Menores Registrados',
      // Dos acciones flotantes (2026-08-24): "+" para registrar una
      // nueva entrada (antes vivía en el ítem de menú aparte "Registro
      // de asistencia", ahora abre exactamente la misma pantalla con
      // `Navigator.push`) y "Salida por manilla" que ya existía. Cada
      // `FloatingActionButton` en pantalla necesita su propio `heroTag`
      // — si no, Flutter lanza un error de tags duplicados.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'salidaPorManilla',
            onPressed: _escanearYDarSalida,
            icon: const Icon(Icons.photo_camera),
            label: const Text('Salida por manilla'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'nuevaAsistencia',
            tooltip: 'Registrar una nueva asistencia',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RegistroAsistenciaScreen(usuario: widget.usuario),
              ),
            ),
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<List<Registro>>(
              stream: _authService.registrosDeHoy(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final presentes = _calcularPresentes(snapshot.data ?? []);
                _asegurarNinosCargados(
                  presentes.where((r) => !r.esVisitante).map((r) => r.fkIdNino),
                );
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
                  // "Mayores de 11 años" ya se lee bien solo — con el
                  // prefijo "Grupo" delante quedaría raro ("Grupo
                  // Mayores de 11 años").
                  : nombre == _sinGrupo
                  ? '$nombre (${registros.length})'
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
        builder: (_) => NinoDetalleSheet(
          nino: nino,
          usuario: usuario,
          registroDeHoy: registro,
        ),
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
    final tieneNoAutorizados = nino?.tieneNoAutorizados ?? false;
    // Los visitantes no tienen ficha (`Nino`), así que no hay ningún
    // registro de autorización de imagen que consultar para ellos — la
    // advertencia solo aplica a niños con ficha completa (2026-08-24,
    // pedido de Rafael).
    final noAutorizaImagen = nino != null && !nino.autorizoFotoFlag;
    final fotoUrl = nino?.fotoUrl ?? '';
    final documento = registro.esVisitante
        ? registro.documentoNinoVisitante
        : (nino?.identificacionMenor ?? '');
    final documentoTexto = documento.isNotEmpty ? documento : 'Sin documento';
    // Los visitantes no tienen fecha de nacimiento registrada (ver
    // docstring de `Registro`), así que solo aplica a niños con ficha —
    // misma lógica exacta de "Cumpleaños niños" (`diasDesdeCumpleanos`).
    final diasDeCumpleanos = nino != null ? diasDesdeCumpleanos(nino.fechaNacimiento) : null;

    return Dismissible(
      key: ValueKey(registro.id),
      direction: DismissDirection.horizontal,
      background: _fondoSalida(Alignment.centerLeft),
      secondaryBackground: _fondoSalida(Alignment.centerRight),
      onDismissed: (_) => onDarSalida(registro),
      child: ListTile(
        onTap: () => _abrirFicha(context),
        leading: FotoAvatar(
          url: fotoUrl,
          iconoSinFoto: Icons.child_care,
          backgroundColor: AppColors.amarillo,
          iconColor: AppColors.textoPrincipal,
        ),
        title: Text(nombre),
        subtitle: Text('$documentoTexto · Manilla ${registro.numeroManilla}'),
        trailing:
            (diasDeCumpleanos == null &&
                !tieneAlertaMedica &&
                !tieneNoAutorizados &&
                !noAutorizaImagen)
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (diasDeCumpleanos != null) ...[
                    _BadgeCumpleanos(dias: diasDeCumpleanos),
                    if (tieneAlertaMedica || tieneNoAutorizados || noAutorizaImagen)
                      const SizedBox(width: 6),
                  ],
                  if (tieneAlertaMedica) ...[
                    const Tooltip(
                      message: 'Tiene condición médica/alergia registrada',
                      child: Icon(Icons.medical_information, color: AppColors.rojo),
                    ),
                    if (tieneNoAutorizados || noAutorizaImagen) const SizedBox(width: 6),
                  ],
                  if (tieneNoAutorizados) ...[
                    const Tooltip(
                      message:
                          'Tiene personas NO autorizadas registradas — revisa su '
                          'ficha antes de dar salida',
                      child: Icon(Icons.person_off, color: AppColors.rojo),
                    ),
                    if (noAutorizaImagen) const SizedBox(width: 6),
                  ],
                  if (noAutorizaImagen)
                    const Tooltip(
                      message: 'NO autoriza uso de imagen — no tomarle fotos ni videos',
                      child: Icon(Icons.no_photography, color: AppColors.rojo),
                    ),
                ],
              ),
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

/// Insignia de cumpleaños (2026-08-20, pedido de Rafael) — mismo criterio
/// de "Cumpleaños niños" (`diasDesdeCumpleanos`), pero como ícono junto
/// al de alerta médica en vez de una pantalla aparte. Reutiliza el
/// degradado de marca de `_avisoCumpleanos()` en
/// `registro_asistencia_screen.dart` para que se sienta consistente con
/// el resto de la app.
class _BadgeCumpleanos extends StatelessWidget {
  final int dias;
  const _BadgeCumpleanos({required this.dias});

  @override
  Widget build(BuildContext context) {
    final mensaje = dias == 0
        ? '¡Cumple años hoy!'
        : dias == 1
        ? 'Cumplió ayer'
        : 'Cumplió hace $dias días';
    return Tooltip(
      message: mensaje,
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.purpura, AppColors.rojo, AppColors.amarillo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: const Icon(Icons.cake, color: Colors.white, size: 15),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 140,
                    child: Text('Teléfono', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(child: Text(registro.telefonoAcudienteVisitante)),
                  IconButton(
                    onPressed: () => llamarTelefono(context, registro.telefonoAcudienteVisitante),
                    icon: const Icon(Icons.call, color: AppColors.azulMarino),
                    tooltip: 'Llamar a ${registro.telefonoAcudienteVisitante}',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
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

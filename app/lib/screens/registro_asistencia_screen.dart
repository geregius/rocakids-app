import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
import '../models/registro.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/escaner_qr.dart';
import '../widgets/app_shell.dart';
import 'editar_acudiente_sheet.dart';
import 'editar_nino_sheet.dart';

enum _Modo { buscar, ninoSeleccionado, visitante }

/// Registro de entrada/salida de niños (SOP §3.3) — la parte operativa
/// central de la app. Fase 1: solo registro manual con conexión a
/// internet (sin escáner QR ni cola offline todavía, ver
/// docs/estado-proyecto.md). Busca un niño ya registrado por nombre, o
/// registra a un niño VISITANTE sin cuenta previa para no rechazar a
/// nadie en la puerta.
class RegistroAsistenciaScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const RegistroAsistenciaScreen({super.key, required this.usuario});

  @override
  State<RegistroAsistenciaScreen> createState() =>
      _RegistroAsistenciaScreenState();
}

class _RegistroAsistenciaScreenState extends State<RegistroAsistenciaScreen> {
  final _authService = AuthService();
  _Modo _modo = _Modo.buscar;

  // Búsqueda de niño ya registrado.
  bool _cargandoIndice = true;
  List<NinoBusqueda> _indice = [];
  final _busquedaController = TextEditingController();
  List<NinoBusqueda> _resultados = [];

  // Niño seleccionado.
  Nino? _nino;
  bool _cargandoDetalle = false;
  Registro? _ultimoMovimiento;
  List<Acudiente> _acudientes = [];
  Acudiente? _acudienteElegido;
  bool _otroAcudiente = false;
  final _otroNombreController = TextEditingController();

  // Completar documento de un niño ya registrado que no lo tenía. Ya no
  // es obligatorio (2026-08-17) — es una advertencia + formulario
  // opcional, no un bloqueo.
  String? _tipoIdentificacionCompletar;
  final _documentoCompletarController = TextEditingController();
  bool _guardandoDocumento = false;
  int? _entradasRecientesSinDocumento;

  // Compartidos entre el formulario de niño registrado y el de visitante.
  String? _servicio;
  final _manillaController = TextEditingController();
  final _observacionController = TextEditingController();

  // Visitante (sin cuenta previa).
  final _nombreVisitanteController = TextEditingController();
  String? _grupoVisitante;
  String? _tipoIdentificacionVisitante;
  final _documentoVisitanteController = TextEditingController();
  final _acudienteVisitanteController = TextEditingController();
  final _telefonoVisitanteController = TextEditingController();
  bool _alertaMedicaVisitante = false;
  final _condicionMedicaVisitanteController = TextEditingController();

  bool _guardando = false;
  String? _error;
  String? _confirmacion;

  @override
  void initState() {
    super.initState();
    _servicio = servicioSugerido();
    _cargarIndice();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _otroNombreController.dispose();
    _documentoCompletarController.dispose();
    _manillaController.dispose();
    _observacionController.dispose();
    _nombreVisitanteController.dispose();
    _documentoVisitanteController.dispose();
    _acudienteVisitanteController.dispose();
    _telefonoVisitanteController.dispose();
    _condicionMedicaVisitanteController.dispose();
    super.dispose();
  }

  Future<void> _cargarIndice() async {
    try {
      final indice = await _authService.obtenerIndiceBusquedaNinos();
      if (mounted) {
        setState(() {
          _indice = indice;
          _cargandoIndice = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoIndice = false);
    }
  }

  void _buscar(String texto) {
    setState(() {
      _resultados = texto.trim().isEmpty
          ? []
          : _indice.where((n) => n.coincideBusqueda(texto)).take(15).toList();
    });
  }

  Future<void> _seleccionarNino(NinoBusqueda resultado) async {
    setState(() {
      _modo = _Modo.ninoSeleccionado;
      _cargandoDetalle = true;
      _resultados = [];
      _error = null;
      _acudienteElegido = null;
      _otroAcudiente = false;
      _servicio = servicioSugerido();
      _manillaController.clear();
      _observacionController.clear();
      _otroNombreController.clear();
      _tipoIdentificacionCompletar = null;
      _documentoCompletarController.clear();
      _entradasRecientesSinDocumento = null;
    });
    try {
      final nino = await _authService.obtenerNinoPorDocumento(
        resultado.documentoIdentificacion,
      );
      if (nino == null) {
        if (mounted) {
          setState(() {
            _cargandoDetalle = false;
            _error =
                'No se encontró el registro completo de ${resultado.nombreCompleto} '
                '(documento: ${resultado.documentoIdentificacion}). '
                'Puede que su ficha esté incompleta — avísale al administrador.';
          });
        }
        return;
      }
      final ultimoMovimiento = await _authService.obtenerUltimoMovimiento(
        nino.documentoIdentificacion,
      );
      final acudientes = await _authService.obtenerAcudientesDeNino(
        nino.documentoIdentificacion,
      );
      // Solo hace falta este conteo si sigue sin documento — es lo que
      // decide si la advertencia es normal o reforzada.
      final entradasRecientes = nino.identificacionMenor.isEmpty
          ? await _authService.contarEntradasUltimoMes(nino.documentoIdentificacion)
          : null;
      if (!mounted) return;
      setState(() {
        _nino = nino;
        _ultimoMovimiento = ultimoMovimiento;
        _acudientes = acudientes;
        _entradasRecientesSinDocumento = entradasRecientes;
        _cargandoDetalle = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargandoDetalle = false;
          _error = 'No se pudo cargar la información del niño: $e';
        });
      }
    }
  }

  String get _accion {
    final ultimo = _ultimoMovimiento;
    if (ultimo == null || ultimo.tipoMovimiento == 'Salida') return 'Entrada';
    return 'Salida';
  }

  /// Escanea el QR de una manilla y llena el campo con el código leído
  /// (2026-08-18, pedido de Rafael) — mismo campo/validación de siempre,
  /// solo cambia cómo se llena. Antes de aceptarlo, revisa que esa
  /// manilla no esté ya puesta en otro niño presente ahora mismo.
  Future<void> _escanearManilla() async {
    final codigo = await escanearCodigoManilla(context);
    if (codigo == null || codigo.isEmpty || !mounted) return;
    final enUso = await _authService.manillaEnUsoHoy(codigo);
    if (!mounted) return;
    if (enUso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta manilla ya está en uso por otro niño presente.'),
        ),
      );
      return;
    }
    setState(() => _manillaController.text = codigo);
  }

  /// Campo de manilla compartido entre el formulario de niño registrado
  /// y el de visitante — con botón de escanear QR junto al texto.
  Widget _campoManilla() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _manillaController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Número de manilla'),
          ),
        ),
        IconButton(
          onPressed: _escanearManilla,
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: 'Escanear manilla',
        ),
      ],
    );
  }

  Future<void> _completarDocumento() async {
    if (_nino == null) return;
    if (_tipoIdentificacionCompletar == null) {
      setState(() => _error = 'Selecciona el tipo de documento.');
      return;
    }
    if (_documentoCompletarController.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa el número de documento.');
      return;
    }

    setState(() {
      _guardandoDocumento = true;
      _error = null;
    });
    try {
      await _authService.completarDocumentoNino(
        documentoIdentificacion: _nino!.documentoIdentificacion,
        tipoIdentificacion: _tipoIdentificacionCompletar!,
        identificacionMenor: _documentoCompletarController.text.trim(),
      );
      final actualizado = await _authService.obtenerNinoPorDocumento(
        _nino!.documentoIdentificacion,
      );
      if (mounted) {
        setState(() {
          _nino = actualizado;
          _guardandoDocumento = false;
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _error = e.mensaje;
        _guardandoDocumento = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo guardar el documento.';
        _guardandoDocumento = false;
      });
    }
  }

  /// Advertencia (no bloqueo, desde 2026-08-17) cuando el niño seleccionado
  /// no tiene documento — se refuerza si ya ha entrado más de 2 veces en
  /// el último mes sin él (`_entradasRecientesSinDocumento`, `null`
  /// mientras se está calculando).
  Widget _avisoSinDocumento() {
    final entradas = _entradasRecientesSinDocumento;
    final alertaFuerte = entradas != null && entradas > 2;
    final color = alertaFuerte ? AppColors.rojo : AppColors.amarillo;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: alertaFuerte ? 0.15 : 0.25),
        borderRadius: BorderRadius.circular(8),
        border: alertaFuerte
            ? Border.all(color: AppColors.rojo, width: 1.5)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            alertaFuerte ? Icons.block : Icons.info_outline,
            color: alertaFuerte ? AppColors.rojo : AppColors.textoPrincipal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alertaFuerte
                  ? 'Este niño no tiene documento y ya ha entrado $entradas '
                        'veces en el último mes sin él. Por favor solicita el '
                        'documento a la familia antes de continuar.'
                  : 'Este niño no tiene número de documento registrado. Se '
                        'recomienda solicitarlo a la familia, pero puedes '
                        'continuar el registro sin él.',
              style: TextStyle(
                color: alertaFuerte ? AppColors.rojo : AppColors.textoPrincipal,
                fontWeight: alertaFuerte ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Aviso festivo (2026-08-18) cuando el niño seleccionado cumplió años
  /// en los últimos 7 días — a propósito bien llamativo (fondo degradado
  /// con los colores de marca, ícono grande) para que no pase
  /// desapercibido y el servidor lo felicite en el momento del check-in.
  Widget _avisoCumpleanos(Nino nino) {
    final dias = diasDesdeCumpleanos(nino.fechaNacimiento)!;
    final mensaje = dias == 0
        ? '¡${nino.nombres} cumple años hoy!'
        : '¡${nino.nombres} estuvo de cumpleaños esta semana!';
    final subtitulo = dias == 0
        ? '¡Es su día especial! Felicítalo/a.'
        : dias == 1
              ? 'Cumplió ayer. Felicítalo/a.'
              : 'Cumplió hace $dias días. Felicítalo/a.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.purpura, AppColors.rojo, AppColors.amarillo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.purpura.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cake, color: AppColors.purpura, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mensaje,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const Icon(Icons.celebration, color: Colors.white, size: 22),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Edita los datos del niño seleccionado ahí mismo, en el momento del
  /// check-in (decisión de Rafael, "para facilitar el proceso") — mismos
  /// campos que ya puede tocar el padre/madre vinculado, ver
  /// [AuthService.editarNino].
  Future<void> _editarNino() async {
    final nino = _nino;
    if (nino == null) return;
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditarNinoSheet(nino: nino),
    );
    if (guardado == true) {
      final actualizado = await _authService.obtenerNinoPorDocumento(
        nino.documentoIdentificacion,
      );
      if (mounted) setState(() => _nino = actualizado);
    }
  }

  /// Edita los datos de un acudiente de la lista, ahí mismo, en el
  /// momento del check-in — misma decisión de Rafael que [_editarNino].
  Future<void> _editarAcudiente(Acudiente acudiente) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditarAcudienteSheet(acudiente: acudiente),
    );
    if (guardado == true && _nino != null) {
      final actualizados = await _authService.obtenerAcudientesDeNino(
        _nino!.documentoIdentificacion,
      );
      if (mounted) {
        setState(() {
          _acudientes = actualizados;
          if (_acudienteElegido != null) {
            _acudienteElegido = actualizados
                .where((a) => a.uid == _acudienteElegido!.uid)
                .firstOrNull;
          }
        });
      }
    }
  }

  void _volverABuscar() {
    setState(() {
      _modo = _Modo.buscar;
      _nino = null;
      _ultimoMovimiento = null;
      _acudientes = [];
      _busquedaController.clear();
      _resultados = [];
      _error = null;
    });
  }

  void _mostrarConfirmacionYReiniciar(String mensaje) {
    setState(() {
      _confirmacion = mensaje;
      _guardando = false;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _confirmacion = null);
      _volverABuscar();
      _nombreVisitanteController.clear();
      _documentoVisitanteController.clear();
      _acudienteVisitanteController.clear();
      _telefonoVisitanteController.clear();
      _condicionMedicaVisitanteController.clear();
      setState(() {
        _grupoVisitante = null;
        _tipoIdentificacionVisitante = null;
        _alertaMedicaVisitante = false;
      });
    });
  }

  Future<void> _registrarMovimientoNino() async {
    if (_nino == null) return;
    if (_servicio == null) {
      setState(() => _error = 'Selecciona el servicio.');
      return;
    }
    if (_manillaController.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa el número de manilla.');
      return;
    }
    final nombreContacto = _otroAcudiente
        ? _otroNombreController.text.trim()
        : (_acudienteElegido?.nombreCompleto ?? '');
    if (nombreContacto.isEmpty) {
      setState(() => _error = 'Indica quién entrega/retira al niño.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    final edad = calcularEdad(_nino!.fechaNacimiento);

    final registro = Registro(
      id: '',
      fkIdNino: _nino!.documentoIdentificacion,
      tipoMovimiento: _accion,
      fechaMovimiento: DateTime.now(),
      numeroManilla: _manillaController.text.trim(),
      fkIdServidor: '',
      nombreServidor: widget.usuario.nombreCompleto,
      fkIdAcudienteContacto: _otroAcudiente
          ? ''
          : (_acudienteElegido?.uid ?? ''),
      nombreAcudienteContacto: nombreContacto,
      servicio: _servicio!,
      grupoEdad: grupoParaEdad(edad) ?? '',
      observacion: _observacionController.text.trim(),
    );

    try {
      await _authService.registrarMovimiento(registro);
      _mostrarConfirmacionYReiniciar(
        '¡$_accion registrada para ${_nino!.nombreCompleto}!',
      );
    } on AuthException catch (e) {
      setState(() {
        _error = e.mensaje;
        _guardando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo registrar el movimiento.';
        _guardando = false;
      });
    }
  }

  Future<void> _registrarVisitante() async {
    if (_nombreVisitanteController.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa el nombre del niño.');
      return;
    }
    if (_grupoVisitante == null) {
      setState(() => _error = 'Selecciona el grupo aproximado del niño.');
      return;
    }
    if (_acudienteVisitanteController.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa el nombre del adulto que lo trae.');
      return;
    }
    if (_servicio == null) {
      setState(() => _error = 'Selecciona el servicio.');
      return;
    }
    if (_manillaController.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa el número de manilla.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    final registro = Registro(
      id: '',
      nombreNinoVisitante: _nombreVisitanteController.text.trim(),
      tipoMovimiento: 'Entrada',
      fechaMovimiento: DateTime.now(),
      numeroManilla: _manillaController.text.trim(),
      fkIdServidor: '',
      nombreServidor: widget.usuario.nombreCompleto,
      nombreAcudienteContacto: _acudienteVisitanteController.text.trim(),
      tipoIdentificacionVisitante: _tipoIdentificacionVisitante ?? '',
      documentoNinoVisitante: _documentoVisitanteController.text.trim(),
      telefonoAcudienteVisitante: _telefonoVisitanteController.text.trim(),
      alertaMedicaVisitante: _alertaMedicaVisitante,
      condicionMedicaVisitante: _alertaMedicaVisitante
          ? _condicionMedicaVisitanteController.text.trim()
          : '',
      servicio: _servicio!,
      grupoEdad: _grupoVisitante!,
      observacion: _observacionController.text.trim(),
    );

    try {
      await _authService.registrarMovimiento(registro);
      _mostrarConfirmacionYReiniciar(
        '¡Entrada registrada para ${_nombreVisitanteController.text.trim()}!',
      );
    } on AuthException catch (e) {
      setState(() {
        _error = e.mensaje;
        _guardando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo registrar el movimiento.';
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Registro de asistencia',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _confirmacion != null
                ? _buildConfirmacion()
                : _buildContenido(),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmacion() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: AppColors.azulMarino, size: 56),
        const SizedBox(height: 16),
        Text(
          _confirmacion!,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildContenido() {
    switch (_modo) {
      case _Modo.buscar:
        return _buildBusqueda();
      case _Modo.ninoSeleccionado:
        return _buildNinoSeleccionado();
      case _Modo.visitante:
        return _buildVisitante();
    }
  }

  Widget _buildBusqueda() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Registro de asistencia',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Busca al niño por nombre para registrar su entrada o salida.',
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _busquedaController,
          enabled: !_cargandoIndice,
          decoration: InputDecoration(
            labelText: 'Nombre del niño',
            suffixIcon: _cargandoIndice
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search),
          ),
          onChanged: _buscar,
        ),
        if (_resultados.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.azulClaro.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _resultados.length,
              itemBuilder: (context, i) {
                final r = _resultados[i];
                return ListTile(
                  dense: true,
                  title: Text(r.nombreCompleto),
                  subtitle: Text('${calcularEdad(r.fechaNacimiento)} años'),
                  onTap: () => _seleccionarNino(r),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _modo = _Modo.visitante;
            _error = null;
            _servicio = servicioSugerido();
          }),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Es la primera vez que viene (visitante)'),
        ),
      ],
    );
  }

  Widget _buildNinoSeleccionado() {
    if (_cargandoDetalle) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final nino = _nino;
    if (nino == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error ?? 'No se encontró la información de este niño.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.rojo),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _volverABuscar,
            child: const Text('Volver a buscar'),
          ),
        ],
      );
    }

    final edad = calcularEdad(nino.fechaNacimiento);
    final grupo = grupoParaEdad(edad);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: _volverABuscar,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Buscar otro niño'),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.amarillo,
                  backgroundImage: nino.fotoUrl.isNotEmpty
                      ? NetworkImage(nino.fotoUrl)
                      : null,
                  child: nino.fotoUrl.isEmpty
                      ? const Icon(
                          Icons.child_care,
                          color: AppColors.textoPrincipal,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nino.nombreCompleto,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        grupo != null
                            ? '$edad años · Grupo $grupo'
                            : '$edad años',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _editarNino,
                  icon: const Icon(Icons.edit),
                  tooltip: 'Editar datos del niño',
                ),
              ],
            ),
          ),
        ),
        if (cumpleEnUltimaSemana(nino.fechaNacimiento)) ...[
          const SizedBox(height: 12),
          _avisoCumpleanos(nino),
        ],
        if (nino.alertaMedicaFlag) ...[
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
                    nino.condicionMedica.isNotEmpty
                        ? nino.condicionMedica
                        : 'Tiene una condición médica/alergia registrada.',
                    style: const TextStyle(color: AppColors.rojo),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (nino.identificacionMenor.isEmpty) ...[
          const SizedBox(height: 16),
          _avisoSinDocumento(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.superficie,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.azulClaro.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Si la familia tiene el documento a la mano, complétalo aquí '
                  '(opcional):',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _tipoIdentificacionCompletar,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de documento',
                  ),
                  items: tiposIdentificacionMenor
                      .where((t) => t != 'No tiene documento')
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _tipoIdentificacionCompletar = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _documentoCompletarController,
                  decoration: const InputDecoration(
                    labelText: 'Número de documento',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _guardandoDocumento ? null : _completarDocumento,
                  child: _guardandoDocumento
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar documento y continuar'),
                ),
              ],
            ),
          ),
        ],
        if (_accion == 'Salida') ...[
          // Este niño ya tiene una Entrada de hoy sin Salida — esta
          // pantalla es solo para registrar ENTRADAS (pedido de Rafael,
          // 2026-08-17). Para darle salida, se hace desde "Menores
          // Recibidos" (deslizando su tarjeta), no buscándolo aquí de
          // nuevo — así se evita que alguien le dé salida por error
          // pensando que estaba registrando otra entrada.
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.amarillo.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.textoPrincipal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Este niño ya tiene una entrada registrada hoy. Para darle '
                    'salida, ve a "Menores Recibidos" y desliza su tarjeta.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 20),
          Text(
            'Registrar ENTRADA',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            '¿Quién lo entrega?',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _otroAcudiente ? 'otro' : _acudienteElegido?.uid,
            onChanged: (v) => setState(() {
              if (v == 'otro') {
                _otroAcudiente = true;
                _acudienteElegido = null;
              } else {
                _otroAcudiente = false;
                _acudienteElegido = _acudientes
                    .where((a) => a.uid == v)
                    .firstOrNull;
              }
            }),
            child: Column(
              children: [
                ..._acudientes.map(
                  (a) => Card(
                    color: _acudienteElegido == a && !_otroAcudiente
                        ? AppColors.azulClaro.withValues(alpha: 0.15)
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            value: a.uid,
                            secondary: CircleAvatar(
                              backgroundImage: a.fotoSeguridadUrl.isNotEmpty
                                  ? NetworkImage(a.fotoSeguridadUrl)
                                  : null,
                              child: a.fotoSeguridadUrl.isEmpty
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(a.nombreCompleto),
                            subtitle: a.estadoAutorizacion == 'Restringido'
                                ? Text(
                                    a.observacionesRestriccion.isNotEmpty
                                        ? 'RESTRINGIDO: ${a.observacionesRestriccion}'
                                        : 'RESTRINGIDO — no debería retirar al niño',
                                    style: const TextStyle(
                                      color: AppColors.rojo,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : a.correoPendienteDeCorregir
                                ? const Text(
                                    'Sin correo real — pídeselo y actualízalo con el lápiz',
                                    style: TextStyle(color: AppColors.textoPrincipal),
                                  )
                                : null,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _editarAcudiente(a),
                          icon: const Icon(Icons.edit),
                          tooltip: 'Editar datos del acudiente',
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: RadioListTile<String>(
                    value: 'otro',
                    secondary: const Icon(Icons.person_outline),
                    title: const Text('Otro (no está en la lista)'),
                  ),
                ),
              ],
            ),
          ),
          if (_otroAcudiente) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _otroNombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre de quien entrega/retira',
              ),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _servicio,
            decoration: const InputDecoration(labelText: 'Servicio'),
            items: serviciosDisponibles
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _servicio = v),
          ),
          const SizedBox(height: 16),
          _campoManilla(),
          const SizedBox(height: 16),
          TextFormField(
            controller: _observacionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.rojo),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _guardando ? null : _registrarMovimientoNino,
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Registrar Entrada'),
          ),
        ],
      ],
    );
  }

  Widget _buildVisitante() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() {
            _modo = _Modo.buscar;
            _error = null;
          }),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Volver a buscar'),
        ),
        const SizedBox(height: 8),
        Text(
          'Registrar niño visitante',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Para un niño que llega por primera vez y todavía no tiene cuenta ni registro. '
          'Solo queda su entrada de hoy — para que tenga ficha completa, un acudiente o un '
          'maestro debe registrarlo formalmente después.',
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nombreVisitanteController,
          decoration: const InputDecoration(
            labelText: 'Nombre completo del niño',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _grupoVisitante,
          decoration: const InputDecoration(
            labelText: 'Grupo aproximado (según su edad)',
          ),
          items: const [
            DropdownMenuItem(value: 'José', child: Text('José (2 años)')),
            DropdownMenuItem(value: 'David', child: Text('David (3-4 años)')),
            DropdownMenuItem(value: 'Judá', child: Text('Judá (5-6 años)')),
            DropdownMenuItem(value: 'Daniel', child: Text('Daniel (7-8 años)')),
            DropdownMenuItem(
              value: 'Santiago',
              child: Text('Santiago (9-10 años)'),
            ),
          ],
          onChanged: (v) => setState(() => _grupoVisitante = v),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _tipoIdentificacionVisitante,
          decoration: const InputDecoration(
            labelText: 'Tipo de documento del niño (opcional)',
          ),
          items: tiposIdentificacionMenor
              .where((t) => t != 'No tiene documento')
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) => setState(() => _tipoIdentificacionVisitante = v),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _documentoVisitanteController,
          decoration: const InputDecoration(
            labelText: 'Número de documento del niño (opcional)',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Si no tiene documento, puedes continuar sin llenar este campo — '
          'recomiéndale a la familia completarlo pronto.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _acudienteVisitanteController,
          decoration: const InputDecoration(
            labelText: 'Nombre del adulto que lo trae',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _telefonoVisitanteController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Teléfono del adulto (opcional)',
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('¿Presenta alguna condición médica o alergia?'),
          value: _alertaMedicaVisitante,
          onChanged: (v) => setState(() => _alertaMedicaVisitante = v ?? false),
        ),
        if (_alertaMedicaVisitante) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _condicionMedicaVisitanteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Detalle de la condición médica / alergia',
            ),
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _servicio,
          decoration: const InputDecoration(labelText: 'Servicio'),
          items: serviciosDisponibles
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() => _servicio = v),
        ),
        const SizedBox(height: 16),
        _campoManilla(),
        const SizedBox(height: 16),
        TextFormField(
          controller: _observacionController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Observación (opcional)',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(color: AppColors.rojo),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _guardando ? null : _registrarVisitante,
          child: _guardando
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Registrar Entrada'),
        ),
      ],
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/foto_picker.dart';
import '../utils/selector_fecha_nacimiento.dart';
import '../widgets/app_shell.dart';

/// Para que un servidor (administrador, columna, líder de ministerio,
/// líder escuela de siervos, maestro principal o auxiliar) registre una
/// familia en su nombre — ej. en la mesa de registro de un servicio,
/// cuando el papá o la mamá no puede hacerlo desde su propio celular.
///
/// "Formulario inteligente": el acudiente y cada niño pueden ser nuevos
/// O ya existir en el sistema, en cualquier combinación. Buscar primero
/// evita duplicar cuentas o fichas.
///
/// Wizard de 3 pasos con transición deslizante (`PageView`, 2026-08-21,
/// pedido de Rafael): 1) datos del acudiente, 2) uno o varios niños
/// (cada uno con su propio parentesco — cubre el caso de un acudiente
/// que es padre de uno y tío de otro en el mismo registro), 3) resumen
/// en tarjetas antes de confirmar. Antes era un solo formulario largo de
/// scroll continuo.
class RegistrarFamiliaScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const RegistrarFamiliaScreen({super.key, required this.usuario});

  @override
  State<RegistrarFamiliaScreen> createState() => _RegistrarFamiliaScreenState();
}

/// Datos de un niño dentro del wizard — cada tarjeta de "Registro del o
/// los menores" tiene su propia instancia, con sus propios controladores
/// (no se pueden compartir entre tarjetas).
class _MenorFormData {
  final busquedaController = TextEditingController();
  final identificacionMenorController = TextEditingController();
  final nombresController = TextEditingController();
  final apellidosController = TextEditingController();
  final condicionMedicaController = TextEditingController();
  String? tipoIdentificacionMenor;
  String? genero;
  String? parentesco;
  DateTime? fechaNacimiento;
  bool autorizaFoto = false;
  bool tieneCondicionMedica = false;
  Uint8List? fotoBytes;
  String? fotoExt;
  NinoBusqueda? encontrado;
  List<NinoBusqueda> resultadosBusqueda = [];

  void dispose() {
    busquedaController.dispose();
    identificacionMenorController.dispose();
    nombresController.dispose();
    apellidosController.dispose();
    condicionMedicaController.dispose();
  }
}

class _RegistrarFamiliaScreenState extends State<RegistrarFamiliaScreen> {
  final _authService = AuthService();
  final _pageController = PageController();
  int _currentStep = 0;

  // Paso 1 — acudiente. Búsqueda por documento (no hay búsqueda por
  // nombre para acudientes, a propósito, por privacidad).
  final _formKeyAcudiente = GlobalKey<FormState>();
  final _numeroDocumentoController = TextEditingController();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _tipoDocumento;
  Acudiente? _acudienteEncontrado;
  bool _buscandoAcudiente = false;
  String? _notaBusquedaAcudiente;
  bool _mostrarPassword = false;
  Uint8List? _fotoAcudienteBytes;
  String? _fotoAcudienteExt;

  // Paso 2 — uno o varios niños. Búsqueda por nombre (reutiliza
  // ninos_busqueda, igual que Registro de asistencia / Agregar hijo).
  bool _cargandoIndiceNinos = true;
  List<NinoBusqueda> _indiceNinos = [];
  List<_MenorFormData> _menores = [_MenorFormData()];

  bool _cargando = false;
  String? _error;
  String? _resumenFamiliaRegistrada;

  @override
  void initState() {
    super.initState();
    _cargarIndiceNinos();
  }

  Future<void> _cargarIndiceNinos() async {
    try {
      final indice = await _authService.obtenerIndiceBusquedaNinos();
      if (mounted) {
        setState(() {
          _indiceNinos = indice;
          _cargandoIndiceNinos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoIndiceNinos = false);
    }
  }

  @override
  void dispose() {
    _numeroDocumentoController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    for (final m in _menores) {
      m.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  // ---- Navegación entre pasos ----

  void _irAPaso(int paso) {
    _pageController.animateToPage(
      paso,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  void _siguientePaso() {
    if (_currentStep == 0) {
      if (!_formKeyAcudiente.currentState!.validate()) return;
    } else if (_currentStep == 1) {
      final error = _validarMenores();
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }
    setState(() => _error = null);
    _irAPaso(_currentStep + 1);
  }

  String? _validarMenores() {
    if (_menores.isEmpty) return 'Agrega al menos un niño.';
    for (var i = 0; i < _menores.length; i++) {
      final m = _menores[i];
      final n = i + 1;
      if (m.parentesco == null) return 'Selecciona el parentesco del niño $n.';
      if (m.encontrado != null) continue;
      if (m.tipoIdentificacionMenor == null) {
        return 'Selecciona el tipo de documento del niño $n.';
      }
      // El número de documento NUNCA es obligatorio para registrar a un
      // niño (2026-08-24, pedido explícito de Rafael) — aunque se haya
      // elegido un tipo de documento real (no "No tiene documento"), se
      // puede dejar el número en blanco si no se tiene a la mano en el
      // momento.
      if (m.nombresController.text.trim().isEmpty ||
          m.apellidosController.text.trim().isEmpty) {
        return 'Completa el nombre del niño $n.';
      }
      if (m.fechaNacimiento == null) {
        return 'Selecciona la fecha de nacimiento del niño $n.';
      }
      if (grupoParaEdad(calcularEdad(m.fechaNacimiento!)) == null) {
        return 'RocaKids recibe niños de $edadMinimaRegistro a '
            '$edadMaximaRegistro años (niño $n).';
      }
      if (m.genero == null) return 'Selecciona el género del niño $n.';
      if (m.tieneCondicionMedica &&
          m.condicionMedicaController.text.trim().isEmpty) {
        return 'Describe la condición médica del niño $n.';
      }
    }
    return null;
  }

  // ---- Acciones del paso 1 (acudiente) ----

  Future<void> _elegirFotoAcudiente() async {
    final foto = await elegirFotoConCamaraOGaleria(context);
    if (foto == null) return;
    setState(() {
      _fotoAcudienteBytes = foto.bytes;
      _fotoAcudienteExt = foto.extension;
    });
  }

  Future<void> _buscarAcudiente() async {
    final numero = _numeroDocumentoController.text.trim();
    if (numero.isEmpty) {
      setState(() => _notaBusquedaAcudiente = 'Ingresa el número de documento para buscar.');
      return;
    }
    setState(() {
      _buscandoAcudiente = true;
      _notaBusquedaAcudiente = null;
    });
    try {
      final encontrado = await _authService.buscarAcudientePorDocumento(numero);
      if (!mounted) return;
      setState(() {
        _acudienteEncontrado = encontrado;
        _buscandoAcudiente = false;
        _notaBusquedaAcudiente = encontrado == null
            ? 'No se encontró ninguna cuenta con ese documento — se creará una nueva.'
            : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _buscandoAcudiente = false;
          _notaBusquedaAcudiente = 'No se pudo buscar: $e';
        });
      }
    }
  }

  void _olvidarAcudienteEncontrado() {
    setState(() {
      _acudienteEncontrado = null;
      _notaBusquedaAcudiente = null;
      _numeroDocumentoController.clear();
    });
  }

  // ---- Acciones del paso 2 (niños) ----

  void _agregarMenor() => setState(() => _menores.add(_MenorFormData()));

  void _quitarMenor(_MenorFormData m) {
    setState(() {
      _menores.remove(m);
      m.dispose();
    });
  }

  Future<void> _elegirFotoMenor(_MenorFormData m) async {
    final foto = await elegirFotoConCamaraOGaleria(context);
    if (foto == null) return;
    setState(() {
      m.fotoBytes = foto.bytes;
      m.fotoExt = foto.extension;
    });
  }

  void _buscarNinoPorNombre(_MenorFormData m, String texto) {
    setState(() {
      m.resultadosBusqueda = texto.trim().isEmpty
          ? []
          : _indiceNinos.where((n) => n.coincideBusqueda(texto)).take(15).toList();
    });
  }

  void _seleccionarNino(_MenorFormData m, NinoBusqueda resultado) {
    final yaAgregadoEnOtraTarjeta = _menores.any(
      (otro) =>
          otro != m &&
          otro.encontrado?.documentoIdentificacion == resultado.documentoIdentificacion,
    );
    if (yaAgregadoEnOtraTarjeta) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya agregaste a este niño en otra tarjeta.')),
      );
      return;
    }
    setState(() {
      m.encontrado = resultado;
      m.resultadosBusqueda = [];
      m.busquedaController.text = resultado.nombreCompleto;
    });
  }

  void _olvidarNinoEncontrado(_MenorFormData m) {
    setState(() {
      m.encontrado = null;
      m.busquedaController.clear();
      m.resultadosBusqueda = [];
    });
  }

  // ---- Envío ----

  Nino _construirNinoNuevo(_MenorFormData m) {
    final tieneDocumento =
        m.tipoIdentificacionMenor != 'No tiene documento' &&
        m.identificacionMenorController.text.trim().isNotEmpty;
    final documentoIdentificacion = tieneDocumento
        ? m.identificacionMenorController.text.trim().toUpperCase()
        : generarLlaveInterna(
            fechaNacimiento: m.fechaNacimiento!,
            nombres: m.nombresController.text,
            apellidos: m.apellidosController.text,
          );
    return Nino(
      documentoIdentificacion: documentoIdentificacion,
      tipoIdentificacion: m.tipoIdentificacionMenor!,
      identificacionMenor: tieneDocumento
          ? m.identificacionMenorController.text.trim()
          : '',
      nombres: m.nombresController.text.trim(),
      apellidos: m.apellidosController.text.trim(),
      fechaNacimiento: m.fechaNacimiento!,
      genero: m.genero!,
      estadoRegistro: 'Activo',
      alertaMedicaFlag: m.tieneCondicionMedica,
      condicionMedica: m.tieneCondicionMedica
          ? m.condicionMedicaController.text.trim()
          : '',
      autorizoFotoFlag: m.autorizaFoto,
    );
  }

  Acudiente _construirAcudienteNuevo() {
    return Acudiente(
      uid: '',
      tipoDocumento: _tipoDocumento!,
      numeroDocumento: _numeroDocumentoController.text.trim(),
      nombres: _nombresController.text.trim(),
      apellidos: _apellidosController.text.trim(),
      telefonoCelular: _telefonoController.text.trim(),
      correoElectronico: _correoController.text.trim(),
    );
  }

  Future<void> _registrar() async {
    if (!_formKeyAcudiente.currentState!.validate()) {
      _irAPaso(0);
      return;
    }
    final errorMenores = _validarMenores();
    if (errorMenores != null) {
      setState(() => _error = errorMenores);
      _irAPaso(1);
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      String acudienteUid;
      String nombreAcudiente;
      if (_acudienteEncontrado != null) {
        acudienteUid = _acudienteEncontrado!.uid;
        nombreAcudiente = _acudienteEncontrado!.nombreCompleto;
      } else {
        final acudienteNuevo = _construirAcudienteNuevo();
        acudienteUid = await _authService.crearAcudienteNuevoDesdeServidor(
          correo: _correoController.text,
          password: _passwordController.text,
          acudiente: acudienteNuevo,
          fotoAcudienteBytes: _fotoAcudienteBytes,
          fotoAcudienteExt: _fotoAcudienteExt,
        );
        nombreAcudiente = acudienteNuevo.nombreCompleto;
      }

      // En paralelo (2026-08-24, pedido de Rafael: "optimiza para que no
      // sea tan demorado") — antes cada niño esperaba a que el anterior
      // terminara por completo (su propia subida de foto + escritura en
      // Firestore), así que una familia de 3 niños tardaba ~3 veces lo
      // que tarda uno solo. Cada niño escribe en SUS PROPIOS documentos
      // (`ninos/{su documento}`, `ninos_busqueda/{su documento}`,
      // `nino_acudiente/{su documento}_{uid del acudiente}`) — nunca el
      // mismo documento que otro niño de la misma familia, así que no
      // hay ningún riesgo de que se pisen entre sí corriendo a la vez.
      final nombresMenores = await Future.wait(
        _menores.map((m) async {
          if (m.encontrado != null) {
            await _authService.vincularNinoAcudienteExistentes(
              documentoNino: m.encontrado!.documentoIdentificacion,
              acudienteUid: acudienteUid,
              parentescoTipo: m.parentesco!,
            );
            return m.encontrado!.nombreCompleto;
          }
          final nino = _construirNinoNuevo(m);
          await _authService.registrarNinoAdicional(
            nino: nino,
            parentescoTipo: m.parentesco!,
            acudienteUid: acudienteUid,
            fotoNinoBytes: m.fotoBytes,
            fotoNinoExt: m.fotoExt,
          );
          return nino.nombreCompleto;
        }),
      );

      if (mounted) {
        setState(() {
          _cargando = false;
          _resumenFamiliaRegistrada = '$nombreAcudiente — ${nombresMenores.join(", ")}';
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.mensaje;
          _cargando = false;
        });
      }
    } catch (e) {
      // Antes SOLO se atrapaba `AuthException` — cualquier otro error
      // (de red, de Storage, un `FirebaseException` crudo) dejaba
      // `_cargando` en `true` PARA SIEMPRE: el botón seguía mostrando
      // el spinner sin ningún mensaje y sin volver a responder. Este
      // era el bug real detrás de "queda ahí bloqueado, no dice nada y
      // no hace nada" (2026-08-24, reportado por Rafael).
      if (mounted) {
        setState(() {
          _error = 'No se pudo completar el registro: $e';
          _cargando = false;
        });
      }
    }
  }

  void _reiniciarFormulario() {
    _formKeyAcudiente.currentState?.reset();
    _numeroDocumentoController.clear();
    _nombresController.clear();
    _apellidosController.clear();
    _telefonoController.clear();
    _correoController.clear();
    _passwordController.clear();
    for (final m in _menores) {
      m.dispose();
    }
    setState(() {
      _tipoDocumento = null;
      _acudienteEncontrado = null;
      _notaBusquedaAcudiente = null;
      _fotoAcudienteBytes = null;
      _fotoAcudienteExt = null;
      _menores = [_MenorFormData()];
      _error = null;
      _resumenFamiliaRegistrada = null;
      _currentStep = 0;
    });
    _pageController.jumpToPage(0);
  }

  String? _requerido(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Registrar familia',
      body: Stack(
        children: [
          _resumenFamiliaRegistrada != null
              ? _buildExito(context)
              : Column(
                  children: [
                    _buildEncabezadoPasos(context),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (i) => setState(() => _currentStep = i),
                        children: [
                          _buildPasoAcudiente(context),
                          _buildPasoMenores(context),
                          _buildPasoResumen(context),
                        ],
                      ),
                    ),
                    _buildBarraNavegacion(context),
                  ],
                ),
          // Overlay bien visible mientras se guarda (2026-08-24, pedido
          // de Rafael: "que aparezca algo de que se está realizando el
          // registro, por favor espere") — cubre toda la pantalla y
          // bloquea cualquier toque de doble envío, no solo el pequeño
          // spinner que ya tenía el botón (fácil de pasar por alto).
          if (_cargando)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Registrando, por favor espera...',
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExito(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.azulMarino, size: 56),
            const SizedBox(height: 16),
            Text(
              '¡Familia registrada!',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_resumenFamiliaRegistrada!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Si se creó una cuenta nueva, ya pueden iniciar sesión con el '
              'correo y la contraseña que ingresaste.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _reiniciarFormulario,
              child: const Text('Registrar otra familia'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncabezadoPasos(BuildContext context) {
    const titulos = ['Datos del acudiente', 'Registro del o los menores', 'Resumen'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (i) {
              final activo = i <= _currentStep;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: activo
                        ? AppColors.azulMarino
                        : AppColors.azulMarino.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Paso ${_currentStep + 1} de 3 · ${titulos[_currentStep]}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildBarraNavegacion(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Row(
          children: [
            if (_currentStep > 0)
              TextButton.icon(
                onPressed: _cargando ? null : () => _irAPaso(_currentStep - 1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Atrás'),
              ),
            const Spacer(),
            ElevatedButton(
              onPressed: _cargando ? null : (_currentStep < 2 ? _siguientePaso : _registrar),
              child: _cargando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_currentStep < 2 ? 'Siguiente' : 'Confirmar y registrar'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Paso 1 ----

  Widget _buildPasoAcudiente(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKeyAcudiente,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Si el acudiente ya tiene cuenta, busca su documento primero '
                  'para no duplicarla.',
                ),
                const SizedBox(height: 16),
                if (_acudienteEncontrado != null)
                  _TarjetaEncontrado(
                    icono: Icons.person,
                    titulo: 'Cuenta encontrada',
                    nombre: _acudienteEncontrado!.nombreCompleto,
                    subtitulo:
                        '${_acudienteEncontrado!.tipoDocumento}: ${_acudienteEncontrado!.numeroDocumento}',
                    fotoUrl: _acudienteEncontrado!.fotoSeguridadUrl,
                    onCambiar: _olvidarAcudienteEncontrado,
                  )
                else if (_buscandoAcudiente)
                  const _TarjetaCargando(mensaje: 'Buscando el documento...')
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _tipoDocumento,
                    decoration: const InputDecoration(labelText: 'Tipo de documento'),
                    items: tiposDocumentoAcudiente
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _tipoDocumento = v),
                    validator: (v) => v == null ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _numeroDocumentoController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Número de documento'),
                          validator: _requerido,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: OutlinedButton(
                          onPressed: _buscandoAcudiente ? null : _buscarAcudiente,
                          child: _buscandoAcudiente
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Buscar'),
                        ),
                      ),
                    ],
                  ),
                  if (_notaBusquedaAcudiente != null) ...[
                    const SizedBox(height: 4),
                    Text(_notaBusquedaAcudiente!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _elegirFotoAcudiente,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
                            backgroundImage: _fotoAcudienteBytes != null
                                ? MemoryImage(_fotoAcudienteBytes!)
                                : null,
                            child: _fotoAcudienteBytes == null
                                ? const Icon(Icons.add_a_photo, size: 28)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fotoAcudienteBytes == null
                              ? 'Foto de seguridad (opcional)'
                              : 'Toca para cambiarla',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nombresController,
                    decoration: const InputDecoration(labelText: 'Nombres'),
                    validator: _requerido,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _apellidosController,
                    decoration: const InputDecoration(labelText: 'Apellidos'),
                    validator: _requerido,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _telefonoController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp'),
                    validator: _requerido,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _correoController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo electrónico'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ingresa el correo';
                      if (!v.contains('@')) return 'Correo inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_mostrarPassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      helperText: 'Defínela junto con la familia — la van a necesitar.',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _mostrarPassword ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.azulMarino,
                        ),
                        tooltip: _mostrarPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                        onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Ingresa una contraseña';
                      if (v.length < 6) return 'Mínimo 6 caracteres';
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Paso 2 ----

  Widget _buildPasoMenores(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Si el niño ya está registrado, búscalo por nombre primero. '
                'Puedes agregar más de uno si son hermanos.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.rojo)),
              ],
              const SizedBox(height: 16),
              for (var i = 0; i < _menores.length; i++) ...[
                _buildTarjetaMenor(context, _menores[i], i),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                onPressed: _agregarMenor,
                icon: const Icon(Icons.add),
                label: const Text('Agregar otro niño'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTarjetaMenor(BuildContext context, _MenorFormData m, int index) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Niño ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_menores.length > 1)
                  IconButton(
                    onPressed: () => _quitarMenor(m),
                    icon: const Icon(Icons.delete_outline, color: AppColors.rojo),
                    tooltip: 'Quitar niño',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (m.encontrado != null)
              _TarjetaEncontrado(
                icono: Icons.child_care,
                titulo: 'Niño encontrado',
                nombre: m.encontrado!.nombreCompleto,
                subtitulo: '${calcularEdad(m.encontrado!.fechaNacimiento)} años',
                fotoUrl: '',
                onCambiar: () => _olvidarNinoEncontrado(m),
              )
            else ...[
              TextFormField(
                controller: m.busquedaController,
                enabled: !_cargandoIndiceNinos,
                decoration: InputDecoration(
                  labelText: 'Buscar niño por nombre',
                  suffixIcon: _cargandoIndiceNinos
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
                onChanged: (texto) => _buscarNinoPorNombre(m, texto),
              ),
              if (m.resultadosBusqueda.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.azulClaro.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: m.resultadosBusqueda.length,
                    itemBuilder: (context, i) {
                      final r = m.resultadosBusqueda[i];
                      return ListTile(
                        dense: true,
                        title: Text(r.nombreCompleto),
                        subtitle: Text('${calcularEdad(r.fechaNacimiento)} años'),
                        onTap: () => _seleccionarNino(m, r),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => _elegirFotoMenor(m),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.amarillo.withValues(alpha: 0.3),
                        backgroundImage: m.fotoBytes != null ? MemoryImage(m.fotoBytes!) : null,
                        child: m.fotoBytes == null
                            ? const Icon(Icons.add_a_photo, size: 28)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.fotoBytes == null ? 'Foto del niño (opcional)' : 'Toca para cambiarla',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: m.tipoIdentificacionMenor,
                decoration: const InputDecoration(labelText: 'Tipo de documento del niño'),
                items: tiposIdentificacionMenor
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => m.tipoIdentificacionMenor = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: m.identificacionMenorController,
                decoration: const InputDecoration(
                  labelText: 'Número de documento del niño (opcional)',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: m.nombresController,
                decoration: const InputDecoration(labelText: 'Nombres del niño'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: m.apellidosController,
                decoration: const InputDecoration(labelText: 'Apellidos del niño'),
              ),
              const SizedBox(height: 16),
              SelectorFechaNacimiento(
                value: m.fechaNacimiento,
                onChanged: (v) => setState(() => m.fechaNacimiento = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: m.genero,
                decoration: const InputDecoration(labelText: 'Género'),
                items: generos.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => m.genero = v),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('¿Autoriza el uso de imagen del niño?'),
                value: m.autorizaFoto,
                onChanged: (v) => setState(() => m.autorizaFoto = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('¿Presenta alguna condición médica o alergia?'),
                value: m.tieneCondicionMedica,
                onChanged: (v) => setState(() => m.tieneCondicionMedica = v ?? false),
              ),
              if (m.tieneCondicionMedica) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: m.condicionMedicaController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Detalle de la condición médica / alergia',
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: m.parentesco,
              decoration: const InputDecoration(labelText: 'Parentesco con el acudiente'),
              items: parentescos.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => m.parentesco = v),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Paso 3 ----

  Widget _buildPasoResumen(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Revisa los datos antes de confirmar.'),
              const SizedBox(height: 16),
              Text('Acudiente', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildResumenAcudiente(context),
              const SizedBox(height: 20),
              Text(
                _menores.length > 1 ? 'Niños' : 'Niño',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _menores.length; i++) ...[
                _buildResumenMenor(context, _menores[i], i),
                const SizedBox(height: 8),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.rojo),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumenAcudiente(BuildContext context) {
    final encontrado = _acudienteEncontrado;
    final nombre = encontrado?.nombreCompleto ??
        '${_nombresController.text} ${_apellidosController.text}'.trim();
    final documento = encontrado != null
        ? '${encontrado.tipoDocumento}: ${encontrado.numeroDocumento}'
        : '${_tipoDocumento ?? ''}: ${_numeroDocumentoController.text}';
    final fotoUrlExistente = encontrado?.fotoSeguridadUrl ?? '';
    return Card(
      color: AppColors.azulClaro.withValues(alpha: 0.1),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.azulClaro.withValues(alpha: 0.3),
          backgroundImage: fotoUrlExistente.isNotEmpty
              ? NetworkImage(fotoUrlExistente)
              : (_fotoAcudienteBytes != null ? MemoryImage(_fotoAcudienteBytes!) : null)
                  as ImageProvider?,
          child: fotoUrlExistente.isEmpty && _fotoAcudienteBytes == null
              ? const Icon(Icons.person)
              : null,
        ),
        title: Text(nombre.trim().isEmpty ? '—' : nombre),
        subtitle: Text(
          '$documento\n${encontrado != null ? "Cuenta ya existente" : "Se creará una cuenta nueva"}',
        ),
        isThreeLine: true,
        trailing: TextButton(onPressed: () => _irAPaso(0), child: const Text('Editar')),
      ),
    );
  }

  Widget _buildResumenMenor(BuildContext context, _MenorFormData m, int index) {
    final encontrado = m.encontrado;
    final nombre = encontrado?.nombreCompleto ??
        '${m.nombresController.text} ${m.apellidosController.text}'.trim();
    final fecha = encontrado?.fechaNacimiento ?? m.fechaNacimiento;
    final edadTxt = fecha != null ? '${calcularEdad(fecha)} años' : '';
    return Card(
      color: AppColors.amarillo.withValues(alpha: 0.08),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.amarillo.withValues(alpha: 0.3),
          backgroundImage: m.fotoBytes != null ? MemoryImage(m.fotoBytes!) : null,
          child: m.fotoBytes == null ? const Icon(Icons.child_care) : null,
        ),
        title: Text(nombre.isEmpty ? 'Niño ${index + 1}' : nombre),
        subtitle: Text(
          '$edadTxt · ${encontrado != null ? "Ya registrado" : "Se creará una ficha nueva"}\n'
          'Parentesco: ${m.parentesco ?? "—"}',
        ),
        isThreeLine: true,
        trailing: TextButton(onPressed: () => _irAPaso(1), child: const Text('Editar')),
      ),
    );
  }
}

/// Ocupa el mismo lugar donde aparecerá `_TarjetaEncontrado` (o el
/// formulario de "nuevo") mientras se espera la respuesta de la
/// búsqueda — para que quede claro que algo está pasando, en vez de que
/// el formulario de "nuevo" se quede quieto sin ningún aviso.
class _TarjetaCargando extends StatelessWidget {
  final String mensaje;
  const _TarjetaCargando({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(mensaje)),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de confirmación cuando la búsqueda (de acudiente o de niño)
/// encuentra a alguien ya existente — reemplaza el formulario de "nuevo"
/// mientras siga seleccionado.
class _TarjetaEncontrado extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String nombre;
  final String subtitulo;
  final String fotoUrl;
  final VoidCallback onCambiar;

  const _TarjetaEncontrado({
    required this.icono,
    required this.titulo,
    required this.nombre,
    required this.subtitulo,
    required this.fotoUrl,
    required this.onCambiar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.azulClaro.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.azulClaro.withValues(alpha: 0.3),
              backgroundImage: fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
              child: fotoUrl.isEmpty ? Icon(icono) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: Theme.of(context).textTheme.bodySmall),
                  Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(subtitulo, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(onPressed: onCambiar, child: const Text('Cambiar')),
          ],
        ),
      ),
    );
  }
}

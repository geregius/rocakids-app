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
/// "Formulario inteligente" (2026-08-17): el acudiente y el niño pueden
/// ser nuevos O ya existir en el sistema, en cualquier combinación —
/// ej. un niño nuevo para un acudiente que ya tiene cuenta, o un
/// acudiente nuevo (papá) para un niño que ya registró la mamá. Buscar
/// por documento antes de llenar el resto evita duplicar cuentas o
/// fichas. Ver [AuthService] para los 4 métodos que cubren cada
/// combinación.
class RegistrarFamiliaScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const RegistrarFamiliaScreen({super.key, required this.usuario});

  @override
  State<RegistrarFamiliaScreen> createState() => _RegistrarFamiliaScreenState();
}

class _RegistrarFamiliaScreenState extends State<RegistrarFamiliaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  // Acudiente — búsqueda por documento (no hay búsqueda por nombre para
  // acudientes, a propósito, por privacidad).
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

  // Niño — búsqueda por nombre (reutiliza ninos_busqueda, igual que
  // Registro de asistencia / Agregar hijo).
  final _busquedaNinoController = TextEditingController();
  final _identificacionMenorController = TextEditingController();
  final _nombresNinoController = TextEditingController();
  final _apellidosNinoController = TextEditingController();
  final _condicionMedicaController = TextEditingController();
  String? _tipoIdentificacionMenor;
  String? _genero;
  DateTime? _fechaNacimiento;
  bool _autorizaFoto = false;
  bool _tieneCondicionMedica = false;
  bool _cargandoIndiceNinos = true;
  List<NinoBusqueda> _indiceNinos = [];
  List<NinoBusqueda> _resultadosNino = [];
  Nino? _ninoEncontrado;
  bool _buscandoNino = false;

  String? _parentesco;
  bool _mostrarPassword = false;
  bool _cargando = false;
  String? _error;
  String? _ultimaFamiliaRegistrada;

  Uint8List? _fotoAcudienteBytes;
  String? _fotoAcudienteExt;
  Uint8List? _fotoNinoBytes;
  String? _fotoNinoExt;

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
    _busquedaNinoController.dispose();
    _identificacionMenorController.dispose();
    _nombresNinoController.dispose();
    _apellidosNinoController.dispose();
    _condicionMedicaController.dispose();
    super.dispose();
  }

  Future<void> _elegirFotoAcudiente() async {
    final archivo = await elegirFotoConCamaraOGaleria(context);
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    setState(() {
      _fotoAcudienteBytes = bytes;
      _fotoAcudienteExt = archivo.name.contains('.')
          ? archivo.name.split('.').last
          : 'jpg';
    });
  }

  Future<void> _elegirFotoNino() async {
    final archivo = await elegirFotoConCamaraOGaleria(context);
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    setState(() {
      _fotoNinoBytes = bytes;
      _fotoNinoExt = archivo.name.contains('.')
          ? archivo.name.split('.').last
          : 'jpg';
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

  void _buscarNinoPorNombre(String texto) {
    setState(() {
      _resultadosNino = texto.trim().isEmpty
          ? []
          : _indiceNinos.where((n) => n.coincideBusqueda(texto)).take(15).toList();
    });
  }

  Future<void> _seleccionarNino(NinoBusqueda resultado) async {
    setState(() {
      _buscandoNino = true;
      _resultadosNino = [];
      _busquedaNinoController.text = resultado.nombreCompleto;
    });
    try {
      final nino = await _authService.obtenerNinoPorDocumento(
        resultado.documentoIdentificacion,
      );
      if (mounted) {
        setState(() {
          _ninoEncontrado = nino;
          _buscandoNino = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _buscandoNino = false;
          _error = 'No se pudo cargar la ficha del niño: $e';
        });
      }
    }
  }

  void _olvidarNinoEncontrado() {
    setState(() {
      _ninoEncontrado = null;
      _busquedaNinoController.clear();
      _resultadosNino = [];
    });
  }

  void _reiniciarFormulario() {
    _formKey.currentState?.reset();
    _numeroDocumentoController.clear();
    _nombresController.clear();
    _apellidosController.clear();
    _telefonoController.clear();
    _correoController.clear();
    _passwordController.clear();
    _busquedaNinoController.clear();
    _identificacionMenorController.clear();
    _nombresNinoController.clear();
    _apellidosNinoController.clear();
    _condicionMedicaController.clear();
    setState(() {
      _tipoDocumento = null;
      _acudienteEncontrado = null;
      _notaBusquedaAcudiente = null;
      _ninoEncontrado = null;
      _resultadosNino = [];
      _tipoIdentificacionMenor = null;
      _genero = null;
      _parentesco = null;
      _fechaNacimiento = null;
      _autorizaFoto = false;
      _tieneCondicionMedica = false;
      _fotoAcudienteBytes = null;
      _fotoAcudienteExt = null;
      _fotoNinoBytes = null;
      _fotoNinoExt = null;
      _ultimaFamiliaRegistrada = null;
    });
  }

  Nino _construirNinoNuevo() {
    final tieneDocumento =
        _tipoIdentificacionMenor != 'No tiene documento' &&
        _identificacionMenorController.text.trim().isNotEmpty;
    final documentoIdentificacion = tieneDocumento
        ? _identificacionMenorController.text.trim().toUpperCase()
        : generarLlaveInterna(
            fechaNacimiento: _fechaNacimiento!,
            nombres: _nombresNinoController.text,
            apellidos: _apellidosNinoController.text,
          );
    return Nino(
      documentoIdentificacion: documentoIdentificacion,
      tipoIdentificacion: _tipoIdentificacionMenor!,
      identificacionMenor: tieneDocumento
          ? _identificacionMenorController.text.trim()
          : '',
      nombres: _nombresNinoController.text.trim(),
      apellidos: _apellidosNinoController.text.trim(),
      fechaNacimiento: _fechaNacimiento!,
      genero: _genero!,
      estadoRegistro: 'Activo',
      alertaMedicaFlag: _tieneCondicionMedica,
      condicionMedica: _tieneCondicionMedica
          ? _condicionMedicaController.text.trim()
          : '',
      autorizoFotoFlag: _autorizaFoto,
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
    if (!_formKey.currentState!.validate()) return;

    final acudienteExistente = _acudienteEncontrado;
    final ninoExistente = _ninoEncontrado;

    if (ninoExistente == null) {
      if (_fechaNacimiento == null) {
        setState(() => _error = 'Selecciona la fecha de nacimiento del niño.');
        return;
      }
      if (grupoParaEdad(calcularEdad(_fechaNacimiento!)) == null) {
        setState(
          () => _error =
              'RocaKids recibe niños de $edadMinimaRegistro a $edadMaximaRegistro años.',
        );
        return;
      }
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      String nombreFamilia;

      if (acudienteExistente == null && ninoExistente == null) {
        // Ambos nuevos: flujo original completo.
        final acudiente = _construirAcudienteNuevo();
        final nino = _construirNinoNuevo();
        await _authService.registrarAcudienteConNinoDesdeServidor(
          correo: _correoController.text,
          password: _passwordController.text,
          acudiente: acudiente,
          nino: nino,
          parentescoTipo: _parentesco!,
          fotoAcudienteBytes: _fotoAcudienteBytes,
          fotoAcudienteExt: _fotoAcudienteExt,
          fotoNinoBytes: _fotoNinoBytes,
          fotoNinoExt: _fotoNinoExt,
        );
        nombreFamilia = acudiente.nombreCompleto;
      } else if (acudienteExistente != null && ninoExistente == null) {
        // Acudiente ya existe, niño nuevo.
        final nino = _construirNinoNuevo();
        await _authService.registrarNinoAdicional(
          nino: nino,
          parentescoTipo: _parentesco!,
          acudienteUid: acudienteExistente.uid,
          fotoNinoBytes: _fotoNinoBytes,
          fotoNinoExt: _fotoNinoExt,
        );
        nombreFamilia = acudienteExistente.nombreCompleto;
      } else if (acudienteExistente == null && ninoExistente != null) {
        // Acudiente nuevo, niño ya existe.
        final acudiente = _construirAcudienteNuevo();
        await _authService.vincularAcudienteNuevoANinoExistenteDesdeServidor(
          correo: _correoController.text,
          password: _passwordController.text,
          acudiente: acudiente,
          documentoNino: ninoExistente.documentoIdentificacion,
          parentescoTipo: _parentesco!,
          fotoAcudienteBytes: _fotoAcudienteBytes,
          fotoAcudienteExt: _fotoAcudienteExt,
        );
        nombreFamilia = acudiente.nombreCompleto;
      } else {
        // Ambos ya existen: solo falta el vínculo.
        await _authService.vincularNinoAcudienteExistentes(
          documentoNino: ninoExistente!.documentoIdentificacion,
          acudienteUid: acudienteExistente!.uid,
          parentescoTipo: _parentesco!,
        );
        nombreFamilia = acudienteExistente.nombreCompleto;
      }

      if (mounted) {
        setState(() {
          _cargando = false;
          _ultimaFamiliaRegistrada = nombreFamilia;
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    }
  }

  String? _requerido(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Registrar familia',
      body: _buildContenido(context),
    );
  }

  Widget _buildContenido(BuildContext context) {
    if (_ultimaFamiliaRegistrada != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.azulMarino,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                '¡Familia de $_ultimaFamiliaRegistrada registrada!',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
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

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Busca primero al acudiente y al niño por si ya existen en el '
                  'sistema — así no se duplican cuentas ni fichas. Si no existen, '
                  'llena sus datos para registrarlos.',
                ),
                const SizedBox(height: 20),
                Text(
                  'Datos del acudiente',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
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
                else ...[
                  const Text(
                    'Si el acudiente ya tiene cuenta, busca su documento primero.',
                    style: TextStyle(fontSize: 13, color: AppColors.textoPrincipal),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _tipoDocumento,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de documento',
                    ),
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
                          decoration: const InputDecoration(
                            labelText: 'Número de documento',
                          ),
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
                    Text(
                      _notaBusquedaAcudiente!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _elegirFotoAcudiente,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.azulClaro.withValues(
                              alpha: 0.2,
                            ),
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
                    decoration: const InputDecoration(
                      labelText: 'Teléfono / WhatsApp',
                    ),
                    validator: _requerido,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _correoController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Ingresa el correo';
                      }
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
                      helperText:
                          'Defínela junto con la familia — la van a necesitar.',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _mostrarPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.azulMarino,
                        ),
                        tooltip: _mostrarPassword
                            ? 'Ocultar contraseña'
                            : 'Mostrar contraseña',
                        onPressed: () =>
                            setState(() => _mostrarPassword = !_mostrarPassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Ingresa una contraseña';
                      if (v.length < 6) return 'Mínimo 6 caracteres';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  'Datos del niño',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (_ninoEncontrado != null)
                  _TarjetaEncontrado(
                    icono: Icons.child_care,
                    titulo: 'Niño encontrado',
                    nombre: _ninoEncontrado!.nombreCompleto,
                    subtitulo:
                        '${calcularEdad(_ninoEncontrado!.fechaNacimiento)} años',
                    fotoUrl: _ninoEncontrado!.fotoUrl,
                    onCambiar: _olvidarNinoEncontrado,
                  )
                else ...[
                  const Text(
                    'Si el niño ya está registrado, búscalo por nombre primero.',
                    style: TextStyle(fontSize: 13, color: AppColors.textoPrincipal),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _busquedaNinoController,
                    enabled: !_cargandoIndiceNinos,
                    decoration: InputDecoration(
                      labelText: 'Buscar niño por nombre',
                      suffixIcon: _cargandoIndiceNinos || _buscandoNino
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
                    onChanged: _buscarNinoPorNombre,
                  ),
                  if (_resultadosNino.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.azulClaro.withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _resultadosNino.length,
                        itemBuilder: (context, i) {
                          final r = _resultadosNino[i];
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
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _elegirFotoNino,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.amarillo.withValues(
                              alpha: 0.3,
                            ),
                            backgroundImage: _fotoNinoBytes != null
                                ? MemoryImage(_fotoNinoBytes!)
                                : null,
                            child: _fotoNinoBytes == null
                                ? const Icon(Icons.add_a_photo, size: 28)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fotoNinoBytes == null
                              ? 'Foto del niño (opcional)'
                              : 'Toca para cambiarla',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _tipoIdentificacionMenor,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de documento del niño',
                    ),
                    items: tiposIdentificacionMenor
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _tipoIdentificacionMenor = v),
                    validator: (v) => v == null ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _identificacionMenorController,
                    decoration: const InputDecoration(
                      labelText: 'Número de documento del niño',
                    ),
                    validator: (v) =>
                        _tipoIdentificacionMenor == 'No tiene documento'
                        ? null
                        : _requerido(v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nombresNinoController,
                    decoration: const InputDecoration(
                      labelText: 'Nombres del niño',
                    ),
                    validator: _requerido,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _apellidosNinoController,
                    decoration: const InputDecoration(
                      labelText: 'Apellidos del niño',
                    ),
                    validator: _requerido,
                  ),
                  const SizedBox(height: 16),
                  SelectorFechaNacimiento(
                    value: _fechaNacimiento,
                    onChanged: (v) => setState(() => _fechaNacimiento = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _genero,
                    decoration: const InputDecoration(labelText: 'Género'),
                    items: generos
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setState(() => _genero = v),
                    validator: (v) => v == null ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('¿Autoriza el uso de imagen del niño?'),
                    value: _autorizaFoto,
                    onChanged: (v) => setState(() => _autorizaFoto = v ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      '¿Presenta alguna condición médica o alergia?',
                    ),
                    value: _tieneCondicionMedica,
                    onChanged: (v) =>
                        setState(() => _tieneCondicionMedica = v ?? false),
                  ),
                  if (_tieneCondicionMedica) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _condicionMedicaController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Detalle de la condición médica / alergia',
                      ),
                      validator: (v) =>
                          _tieneCondicionMedica ? _requerido(v) : null,
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _parentesco,
                  decoration: const InputDecoration(
                    labelText: 'Parentesco del acudiente con el niño',
                  ),
                  items: parentescos
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _parentesco = v),
                  validator: (v) => v == null ? 'Requerido' : null,
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
                  onPressed: _cargando ? null : _registrar,
                  child: _cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Registrar'),
                ),
              ],
            ),
          ),
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

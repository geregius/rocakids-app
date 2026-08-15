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
/// familia nueva en nombre de ella — ej. en la mesa de registro de un servicio,
/// cuando el papá o la mamá no puede hacerlo desde su propio celular.
/// Mismo formulario que el auto-registro público de acudiente, pero
/// quien lo llena es un servidor que ya tiene su propia sesión abierta
/// (ver [AuthService.registrarAcudienteConNinoDesdeServidor]) — al
/// terminar, se puede registrar otra familia sin perder esa sesión.
class RegistrarFamiliaScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const RegistrarFamiliaScreen({super.key, required this.usuario});

  @override
  State<RegistrarFamiliaScreen> createState() => _RegistrarFamiliaScreenState();
}

class _RegistrarFamiliaScreenState extends State<RegistrarFamiliaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  // Acudiente
  final _numeroDocumentoController = TextEditingController();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _tipoDocumento;

  // Niño
  final _identificacionMenorController = TextEditingController();
  final _nombresNinoController = TextEditingController();
  final _apellidosNinoController = TextEditingController();
  final _condicionMedicaController = TextEditingController();
  String? _tipoIdentificacionMenor;
  String? _genero;
  String? _parentesco;
  DateTime? _fechaNacimiento;
  bool _autorizaFoto = false;
  bool _tieneCondicionMedica = false;

  bool _mostrarPassword = false;
  bool _cargando = false;
  String? _error;
  String? _ultimaFamiliaRegistrada;

  Uint8List? _fotoAcudienteBytes;
  String? _fotoAcudienteExt;
  Uint8List? _fotoNinoBytes;
  String? _fotoNinoExt;

  @override
  void dispose() {
    _numeroDocumentoController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
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

  void _reiniciarFormulario() {
    _formKey.currentState?.reset();
    _numeroDocumentoController.clear();
    _nombresController.clear();
    _apellidosController.clear();
    _telefonoController.clear();
    _correoController.clear();
    _passwordController.clear();
    _identificacionMenorController.clear();
    _nombresNinoController.clear();
    _apellidosNinoController.clear();
    _condicionMedicaController.clear();
    setState(() {
      _tipoDocumento = null;
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

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
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

    setState(() {
      _cargando = true;
      _error = null;
    });

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

    final acudiente = Acudiente(
      uid: '',
      tipoDocumento: _tipoDocumento!,
      numeroDocumento: _numeroDocumentoController.text.trim(),
      nombres: _nombresController.text.trim(),
      apellidos: _apellidosController.text.trim(),
      telefonoCelular: _telefonoController.text.trim(),
      correoElectronico: _correoController.text.trim(),
    );

    final nino = Nino(
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

    final nombreFamilia = acudiente.nombreCompleto;

    try {
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
                'Ya pueden iniciar sesión con el correo y la contraseña que ingresaste.',
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
                  'Registra a una familia nueva (acudiente + niño) en su nombre. '
                  'Ellos podrán iniciar sesión después con el correo y la contraseña '
                  'que definas acá.',
                ),
                const SizedBox(height: 20),
                Text(
                  'Datos del acudiente',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
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
                TextFormField(
                  controller: _numeroDocumentoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Número de documento',
                  ),
                  validator: _requerido,
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
                const SizedBox(height: 28),
                Text(
                  'Datos del niño',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
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
                      : const Text('Registrar familia'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

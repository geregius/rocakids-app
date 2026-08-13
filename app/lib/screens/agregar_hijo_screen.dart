import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/foto_picker.dart';

enum _Modo { elegir, vincular, nuevo }

/// Desde el portal del acudiente: vincular un niño ya registrado (por
/// otro acudiente) o registrar uno nuevo.
class AgregarHijoScreen extends StatefulWidget {
  const AgregarHijoScreen({super.key});

  @override
  State<AgregarHijoScreen> createState() => _AgregarHijoScreenState();
}

class _AgregarHijoScreenState extends State<AgregarHijoScreen> {
  _Modo _modo = _Modo.elegir;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar hijo')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: switch (_modo) {
                _Modo.elegir => _SelectorModo(onElegir: (m) => setState(() => _modo = m)),
                _Modo.vincular => const _VincularNinoForm(),
                _Modo.nuevo => const _NuevoNinoForm(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectorModo extends StatelessWidget {
  final void Function(_Modo) onElegir;
  const _SelectorModo({required this.onElegir});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿Cómo quieres agregarlo?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => onElegir(_Modo.vincular),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Ya está registrado (por otro acudiente)'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => onElegir(_Modo.nuevo),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Es la primera vez que lo registro'),
          ),
        ),
      ],
    );
  }
}

class _VincularNinoForm extends StatefulWidget {
  const _VincularNinoForm();

  @override
  State<_VincularNinoForm> createState() => _VincularNinoFormState();
}

class _VincularNinoFormState extends State<_VincularNinoForm> {
  final _formKey = GlobalKey<FormState>();
  final _documentoController = TextEditingController();
  String? _parentesco;
  bool _cargando = false;
  String? _error;
  Nino? _encontrado;

  @override
  void dispose() {
    _documentoController.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final nino = await AuthService().vincularNinoExistente(
        documentoNino: _documentoController.text,
        parentescoTipo: _parentesco!,
      );
      setState(() => _encontrado = nino);
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_encontrado != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.azulMarino, size: 48),
          const SizedBox(height: 12),
          Text('¡Vinculado con ${_encontrado!.nombreCompleto}!', textAlign: TextAlign.center),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Vincular niño existente', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text('Ingresa el número de documento con el que ya fue registrado.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _documentoController,
            decoration: const InputDecoration(labelText: 'Número de documento del niño'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _parentesco,
            decoration: const InputDecoration(labelText: 'Tu parentesco con el niño'),
            items: parentescos.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) => setState(() => _parentesco = v),
            validator: (v) => v == null ? 'Requerido' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.rojo), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _cargando ? null : _vincular,
            child: _cargando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Vincular'),
          ),
        ],
      ),
    );
  }
}

class _NuevoNinoForm extends StatefulWidget {
  const _NuevoNinoForm();

  @override
  State<_NuevoNinoForm> createState() => _NuevoNinoFormState();
}

class _NuevoNinoFormState extends State<_NuevoNinoForm> {
  final _formKey = GlobalKey<FormState>();
  final _identificacionMenorController = TextEditingController();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _condicionMedicaController = TextEditingController();
  String? _tipoIdentificacion;
  String? _genero;
  String? _parentesco;
  DateTime? _fechaNacimiento;
  bool _autorizaFoto = false;
  bool _tieneCondicionMedica = false;
  bool _cargando = false;
  String? _error;
  Uint8List? _fotoBytes;
  String? _fotoExt;

  @override
  void dispose() {
    _identificacionMenorController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _condicionMedicaController.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto() async {
    final archivo = await elegirFotoConCamaraOGaleria(context);
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    setState(() {
      _fotoBytes = bytes;
      _fotoExt = archivo.name.contains('.') ? archivo.name.split('.').last : 'jpg';
    });
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime(DateTime.now().year - 5),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (fecha != null) setState(() => _fechaNacimiento = fecha);
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fechaNacimiento == null) {
      setState(() => _error = 'Selecciona la fecha de nacimiento.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    final tieneDocumento = _tipoIdentificacion != 'No tiene documento' &&
        _identificacionMenorController.text.trim().isNotEmpty;
    final documentoIdentificacion = tieneDocumento
        ? _identificacionMenorController.text.trim().toUpperCase()
        : generarLlaveInterna(
            fechaNacimiento: _fechaNacimiento!,
            nombres: _nombresController.text,
            apellidos: _apellidosController.text,
          );

    final nino = Nino(
      documentoIdentificacion: documentoIdentificacion,
      tipoIdentificacion: _tipoIdentificacion!,
      identificacionMenor: tieneDocumento ? _identificacionMenorController.text.trim() : '',
      nombres: _nombresController.text.trim(),
      apellidos: _apellidosController.text.trim(),
      fechaNacimiento: _fechaNacimiento!,
      genero: _genero!,
      estadoRegistro: 'Activo',
      alertaMedicaFlag: _tieneCondicionMedica,
      condicionMedica: _tieneCondicionMedica ? _condicionMedicaController.text.trim() : '',
      autorizoFotoFlag: _autorizaFoto,
    );

    try {
      await AuthService().registrarNinoAdicional(
        nino: nino,
        parentescoTipo: _parentesco!,
        fotoNinoBytes: _fotoBytes,
        fotoNinoExt: _fotoExt,
      );
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String? _requerido(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Registrar niño nuevo', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _elegirFoto,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.amarillo.withValues(alpha: 0.3),
                    backgroundImage: _fotoBytes != null ? MemoryImage(_fotoBytes!) : null,
                    child: _fotoBytes == null ? const Icon(Icons.add_a_photo, size: 28) : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fotoBytes == null ? 'Foto del niño (opcional)' : 'Toca para cambiarla',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _tipoIdentificacion,
            decoration: const InputDecoration(labelText: 'Tipo de documento'),
            items: tiposIdentificacionMenor
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _tipoIdentificacion = v),
            validator: (v) => v == null ? 'Requerido' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _identificacionMenorController,
            decoration: const InputDecoration(labelText: 'Número de documento'),
            validator: (v) => _tipoIdentificacion == 'No tiene documento' ? null : _requerido(v),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fecha de nacimiento'),
            subtitle: Text(
              _fechaNacimiento != null
                  ? '${_fechaNacimiento!.day.toString().padLeft(2, '0')}/'
                      '${_fechaNacimiento!.month.toString().padLeft(2, '0')}/'
                      '${_fechaNacimiento!.year}'
                  : 'Toca para seleccionar',
            ),
            trailing: const Icon(Icons.calendar_month, color: AppColors.azulMarino),
            onTap: _elegirFecha,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _genero,
            decoration: const InputDecoration(labelText: 'Género'),
            items: generos.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
            onChanged: (v) => setState(() => _genero = v),
            validator: (v) => v == null ? 'Requerido' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _parentesco,
            decoration: const InputDecoration(labelText: 'Tu parentesco con el niño'),
            items: parentescos.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) => setState(() => _parentesco = v),
            validator: (v) => v == null ? 'Requerido' : null,
          ),
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
            title: const Text('¿Presenta alguna condición médica o alergia?'),
            value: _tieneCondicionMedica,
            onChanged: (v) => setState(() => _tieneCondicionMedica = v ?? false),
          ),
          if (_tieneCondicionMedica) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _condicionMedicaController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Detalle de la condición médica / alergia'),
              validator: (v) => _tieneCondicionMedica ? _requerido(v) : null,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.rojo), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _cargando ? null : _registrar,
            child: _cargando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Registrar niño'),
          ),
        ],
      ),
    );
  }
}

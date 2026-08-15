import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// Formulario para editar los datos de contacto/documento de un
/// acudiente ya registrado. Quién puede abrir esto lo decide quien
/// llama (panel admin, o check-in/out) — este formulario en sí no
/// vuelve a chequear el rol, confía en que las reglas de seguridad son
/// la barrera real. A propósito no incluye el estado de autorización ni
/// las observaciones de restricción (esos quedan admin-only, ver
/// [AuthService.editarAcudiente]).
class EditarAcudienteSheet extends StatefulWidget {
  final Acudiente acudiente;

  const EditarAcudienteSheet({super.key, required this.acudiente});

  @override
  State<EditarAcudienteSheet> createState() => _EditarAcudienteSheetState();
}

class _EditarAcudienteSheetState extends State<EditarAcudienteSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numeroDocumentoController;
  late final TextEditingController _nombresController;
  late final TextEditingController _apellidosController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _correoController;
  late String? _tipoDocumento;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.acudiente;
    _tipoDocumento = a.tipoDocumento;
    _numeroDocumentoController = TextEditingController(text: a.numeroDocumento);
    _nombresController = TextEditingController(text: a.nombres);
    _apellidosController = TextEditingController(text: a.apellidos);
    _telefonoController = TextEditingController(text: a.telefonoCelular);
    _correoController = TextEditingController(text: a.correoElectronico);
  }

  @override
  void dispose() {
    _numeroDocumentoController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await AuthService().editarAcudiente(
        uid: widget.acudiente.uid,
        tipoDocumento: _tipoDocumento!,
        numeroDocumento: _numeroDocumentoController.text.trim(),
        nombres: _nombresController.text.trim(),
        apellidos: _apellidosController.text.trim(),
        telefonoCelular: _telefonoController.text.trim(),
        correoElectronico: _correoController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String? _requerido(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Editar acudiente', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
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
              TextFormField(
                controller: _numeroDocumentoController,
                decoration: const InputDecoration(labelText: 'Número de documento'),
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
                decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp'),
                validator: _requerido,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _correoController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo electrónico'),
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
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

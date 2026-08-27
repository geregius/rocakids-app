import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/selector_fecha_nacimiento.dart';

/// Formulario para editar los datos básicos de un niño ya registrado.
/// Quién puede abrir esto lo decide [NinoDetalleSheet] (padre/madre
/// vinculado, o admin) — este formulario en sí no vuelve a chequear el
/// rol, confía en que las reglas de seguridad son la barrera real.
/// A propósito no incluye el documento del menor ni su foto (ver
/// [AuthService.editarNino]).
class EditarNinoSheet extends StatefulWidget {
  final Nino nino;

  const EditarNinoSheet({super.key, required this.nino});

  @override
  State<EditarNinoSheet> createState() => _EditarNinoSheetState();
}

class _EditarNinoSheetState extends State<EditarNinoSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombresController;
  late final TextEditingController _apellidosController;
  late final TextEditingController _condicionMedicaController;
  late String? _genero;
  late DateTime? _fechaNacimiento;
  late bool _autorizaFoto;
  late bool _tieneCondicionMedica;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final nino = widget.nino;
    _nombresController = TextEditingController(text: nino.nombres);
    _apellidosController = TextEditingController(text: nino.apellidos);
    _condicionMedicaController = TextEditingController(text: nino.condicionMedica);
    _genero = nino.genero;
    _fechaNacimiento = nino.fechaNacimiento;
    _autorizaFoto = nino.autorizoFotoFlag;
    _tieneCondicionMedica = nino.alertaMedicaFlag;
  }

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
    _condicionMedicaController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fechaNacimiento == null) {
      setState(() => _error = 'Selecciona la fecha de nacimiento.');
      return;
    }
    // Mayor de edadMaximaRegistro NO bloquea el registro (2026-08-27,
    // pedido de Rafael) — solo se advierte en el selector de fecha. RocaKids
    // sigue sin recibir bebés de cuna, así que eso sí bloquea.
    if (calcularEdad(_fechaNacimiento!) < edadMinimaRegistro) {
      setState(
        () => _error =
            'RocaKids recibe niños de $edadMinimaRegistro a $edadMaximaRegistro años.',
      );
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await AuthService().editarNino(
        documentoIdentificacion: widget.nino.documentoIdentificacion,
        nombres: _nombresController.text.trim(),
        apellidos: _apellidosController.text.trim(),
        fechaNacimiento: _fechaNacimiento!,
        genero: _genero!,
        autorizoFotoFlag: _autorizaFoto,
        alertaMedicaFlag: _tieneCondicionMedica,
        condicionMedica: _condicionMedicaController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar: $e');
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
              Text('Editar información', style: Theme.of(context).textTheme.titleLarge),
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
              SelectorFechaNacimiento(
                value: _fechaNacimiento,
                onChanged: (v) => setState(() => _fechaNacimiento = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _genero,
                decoration: const InputDecoration(labelText: 'Género'),
                items: generos.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => _genero = v),
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
                  decoration: const InputDecoration(
                    labelText: 'Detalle de la condición médica / alergia',
                  ),
                  validator: (v) => _tieneCondicionMedica ? _requerido(v) : null,
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

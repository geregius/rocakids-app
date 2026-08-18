import 'package:flutter/material.dart';

import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/foto_picker.dart';

/// Formulario para editar los datos de perfil de un servidor (documento,
/// EPS, contacto de emergencia, etc). Lo usan dos casos:
/// - Un admin corrigiendo el perfil de cualquier servidor.
/// - El propio servidor editando su perfil (ahí sí puede cambiar su foto;
///   las reglas de Storage no dejan que un admin suba la foto de otro).
class EditPerfilServidorSheet extends StatefulWidget {
  final UsuarioApp usuario;
  final bool esPropio;

  const EditPerfilServidorSheet({
    super.key,
    required this.usuario,
    required this.esPropio,
  });

  @override
  State<EditPerfilServidorSheet> createState() => _EditPerfilServidorSheetState();
}

class _EditPerfilServidorSheetState extends State<EditPerfilServidorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  late final TextEditingController _numeroDocumentoController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _epsController;
  late final TextEditingController _contactoNombreController;
  late final TextEditingController _contactoTelefonoController;

  String? _tipoDocumento;
  String? _grupoSanguineo;
  late String _fotoUrl;

  bool _subiendoFoto = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    _numeroDocumentoController = TextEditingController(text: u.numeroDocumento);
    _telefonoController = TextEditingController(text: u.telefono);
    _epsController = TextEditingController(text: u.epsNombre);
    _contactoNombreController = TextEditingController(text: u.contactoEmergenciaNombre);
    _contactoTelefonoController = TextEditingController(text: u.contactoEmergenciaTelefono);
    _tipoDocumento = u.tipoDocumento.isNotEmpty ? u.tipoDocumento : null;
    _grupoSanguineo = u.grupoSanguineo.isNotEmpty ? u.grupoSanguineo : null;
    _fotoUrl = u.fotoUrl;
  }

  @override
  void dispose() {
    _numeroDocumentoController.dispose();
    _telefonoController.dispose();
    _epsController.dispose();
    _contactoNombreController.dispose();
    _contactoTelefonoController.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto() async {
    try {
      final archivo = await elegirFotoConCamaraOGaleria(context);
      if (archivo == null) return;

      setState(() => _subiendoFoto = true);
      final bytes = await archivo.readAsBytes();
      final extension = archivo.name.contains('.') ? archivo.name.split('.').last : 'jpg';
      final url = await _authService.subirFotoServidor(bytes, extension);
      setState(() => _fotoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo subir la foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await _authService.completarPerfilServidor(
        uid: widget.usuario.uid,
        tipoDocumento: _tipoDocumento!,
        numeroDocumento: _numeroDocumentoController.text.trim(),
        telefono: _telefonoController.text.trim(),
        epsNombre: _epsController.text.trim(),
        grupoSanguineo: _grupoSanguineo!,
        contactoEmergenciaNombre: _contactoNombreController.text.trim(),
        contactoEmergenciaTelefono: _contactoTelefonoController.text.trim(),
        fotoUrl: _fotoUrl,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
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
              if (widget.esPropio)
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _subiendoFoto ? null : _elegirFoto,
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
                          backgroundImage: _fotoUrl.isNotEmpty ? NetworkImage(_fotoUrl) : null,
                          child: _subiendoFoto
                              ? const CircularProgressIndicator()
                              : (_fotoUrl.isEmpty ? const Icon(Icons.add_a_photo) : null),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Toca para cambiar tu foto', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: widget.usuario.correo,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Correo electrónico'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _tipoDocumento,
                decoration: const InputDecoration(labelText: 'Tipo de documento'),
                items: tiposDocumento.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _tipoDocumento = v),
                validator: (v) => v == null ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _numeroDocumentoController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Número de documento'),
                validator: _requerido,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                validator: _requerido,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _epsController,
                decoration: const InputDecoration(labelText: 'EPS'),
                validator: _requerido,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _grupoSanguineo,
                decoration: const InputDecoration(labelText: 'Grupo sanguíneo'),
                items: gruposSanguineos.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => _grupoSanguineo = v),
                validator: (v) => v == null ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),
              Text('Contacto de emergencia', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contactoNombreController,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: _requerido,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactoTelefonoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                validator: _requerido,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: AppColors.rojo), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: (_guardando || _subiendoFoto) ? null : _guardar,
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

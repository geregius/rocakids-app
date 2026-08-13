import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// Formulario obligatorio y bloqueante: un servidor con rol ya asignado
/// no puede usar ninguna otra parte de la app hasta llenar todos estos
/// datos (tabla SERVIDORES del SOP).
class CompleteProfileScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const CompleteProfileScreen({super.key, required this.usuario});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  late final TextEditingController _numeroDocumentoController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _epsController;
  late final TextEditingController _contactoNombreController;
  late final TextEditingController _contactoTelefonoController;

  String? _tipoDocumento;
  String? _grupoSanguineo;
  String _fotoUrl = '';

  bool _subiendoFoto = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _numeroDocumentoController = TextEditingController(text: widget.usuario.numeroDocumento);
    _telefonoController = TextEditingController(text: widget.usuario.telefono);
    _epsController = TextEditingController(text: widget.usuario.epsNombre);
    _contactoNombreController = TextEditingController(text: widget.usuario.contactoEmergenciaNombre);
    _contactoTelefonoController = TextEditingController(text: widget.usuario.contactoEmergenciaTelefono);
    _tipoDocumento = widget.usuario.tipoDocumento.isNotEmpty ? widget.usuario.tipoDocumento : null;
    _grupoSanguineo = widget.usuario.grupoSanguineo.isNotEmpty ? widget.usuario.grupoSanguineo : null;
    _fotoUrl = widget.usuario.fotoUrl;
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
      final archivo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
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
    if (_fotoUrl.isEmpty) {
      setState(() => _error = 'Debes subir tu foto de perfil.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await _authService.completarPerfilServidor(
        tipoDocumento: _tipoDocumento!,
        numeroDocumento: _numeroDocumentoController.text.trim(),
        telefono: _telefonoController.text.trim(),
        epsNombre: _epsController.text.trim(),
        grupoSanguineo: _grupoSanguineo!,
        contactoEmergenciaNombre: _contactoNombreController.text.trim(),
        contactoEmergenciaTelefono: _contactoTelefonoController.text.trim(),
        fotoUrl: _fotoUrl,
      );
      // El AuthGate reacciona solo: al guardar, perfilCompleto pasa a
      // true y la pantalla cambia sin que tengamos que navegar aquí.
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String? _requerido(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa tu perfil'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => _authService.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Bienvenido, ${widget.usuario.nombre}. Tu rol (${widget.usuario.rol.etiqueta}) '
                      'ya fue aprobado. Antes de continuar, completa estos datos — '
                      'son obligatorios para poder usar la app.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: _subiendoFoto ? null : _elegirFoto,
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
                          backgroundImage: _fotoUrl.isNotEmpty ? NetworkImage(_fotoUrl) : null,
                          child: _subiendoFoto
                              ? const CircularProgressIndicator()
                              : (_fotoUrl.isEmpty
                                  ? const Icon(Icons.add_a_photo, size: 32)
                                  : null),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        _fotoUrl.isEmpty ? 'Toca para subir tu foto' : 'Toca para cambiar tu foto',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: _tipoDocumento,
                      decoration: const InputDecoration(labelText: 'Tipo de documento'),
                      items: tiposDocumento
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
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
                      items: gruposSanguineos
                          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
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
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: (_guardando || _subiendoFoto) ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Guardar y continuar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

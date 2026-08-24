import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/foto_picker.dart';

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
  int? _diaNacimiento;
  int? _mesNacimiento;
  int? _anioNacimiento;

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
    _diaNacimiento = widget.usuario.fechaNacimiento?.day;
    _mesNacimiento = widget.usuario.fechaNacimiento?.month;
    _anioNacimiento = widget.usuario.fechaNacimiento?.year;
  }

  DateTime? get _fechaNacimientoElegida {
    if (_diaNacimiento == null || _mesNacimiento == null || _anioNacimiento == null) {
      return null;
    }
    return DateTime(_anioNacimiento!, _mesNacimiento!, _diaNacimiento!);
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
      final foto = await elegirFotoConCamaraOGaleria(context);
      if (foto == null) return;

      setState(() => _subiendoFoto = true);
      final url = await _authService.subirFotoServidor(foto.bytes, foto.extension);
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
    if (_fechaNacimientoElegida == null) {
      setState(() => _error = 'Selecciona tu fecha de nacimiento.');
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
        fechaNacimiento: _fechaNacimientoElegida,
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
                    Text(
                      'Fecha de nacimiento',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            initialValue: _diaNacimiento,
                            decoration: const InputDecoration(labelText: 'Día'),
                            items: List.generate(
                              31,
                              (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                            ),
                            onChanged: (v) => setState(() => _diaNacimiento = v),
                            validator: (v) => v == null ? 'Requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<int>(
                            initialValue: _mesNacimiento,
                            decoration: const InputDecoration(labelText: 'Mes'),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('Enero')),
                              DropdownMenuItem(value: 2, child: Text('Febrero')),
                              DropdownMenuItem(value: 3, child: Text('Marzo')),
                              DropdownMenuItem(value: 4, child: Text('Abril')),
                              DropdownMenuItem(value: 5, child: Text('Mayo')),
                              DropdownMenuItem(value: 6, child: Text('Junio')),
                              DropdownMenuItem(value: 7, child: Text('Julio')),
                              DropdownMenuItem(value: 8, child: Text('Agosto')),
                              DropdownMenuItem(value: 9, child: Text('Septiembre')),
                              DropdownMenuItem(value: 10, child: Text('Octubre')),
                              DropdownMenuItem(value: 11, child: Text('Noviembre')),
                              DropdownMenuItem(value: 12, child: Text('Diciembre')),
                            ],
                            onChanged: (v) => setState(() => _mesNacimiento = v),
                            validator: (v) => v == null ? 'Requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            initialValue: _anioNacimiento,
                            decoration: const InputDecoration(labelText: 'Año'),
                            items: List.generate(
                              76,
                              (i) => DropdownMenuItem(
                                value: DateTime.now().year - 15 - i,
                                child: Text('${DateTime.now().year - 15 - i}'),
                              ),
                            ),
                            onChanged: (v) => setState(() => _anioNacimiento = v),
                            validator: (v) => v == null ? 'Requerido' : null,
                          ),
                        ),
                      ],
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

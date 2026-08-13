import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/foto_picker.dart';
import 'agregar_hijo_screen.dart';

/// Portal de "Mis hijos": accesible para CUALQUIER usuario logueado, sin
/// importar su rol (un administrador o un maestro también puede tener
/// hijos propios registrados con la misma cuenta). Si todavía no tiene
/// perfil de acudiente, primero se lo pide; luego muestra sus niños.
class AcudientePortalScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const AcudientePortalScreen({super.key, required this.usuario});

  @override
  State<AcudientePortalScreen> createState() => _AcudientePortalScreenState();
}

class _AcudientePortalScreenState extends State<AcudientePortalScreen> {
  late Future<Acudiente?> _acudienteFuture;

  @override
  void initState() {
    super.initState();
    _acudienteFuture = AuthService().obtenerMiAcudiente();
  }

  void _recargar() => setState(() {
    _acudienteFuture = AuthService().obtenerMiAcudiente();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis hijos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: FutureBuilder<Acudiente?>(
        future: _acudienteFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.data == null) {
            return _RegistroAcudienteForm(usuario: widget.usuario, onListo: _recargar);
          }
          return _ListaDeHijos(usuario: widget.usuario);
        },
      ),
    );
  }
}

class _ListaDeHijos extends StatefulWidget {
  final UsuarioApp usuario;
  const _ListaDeHijos({required this.usuario});

  @override
  State<_ListaDeHijos> createState() => _ListaDeHijosState();
}

class _ListaDeHijosState extends State<_ListaDeHijos> {
  late Future<List<Nino>> _hijosFuture;

  @override
  void initState() {
    super.initState();
    _cargarHijos();
  }

  void _cargarHijos() {
    _hijosFuture = AuthService().obtenerMisHijos();
  }

  Future<void> _abrirAgregarHijo() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AgregarHijoScreen()),
    );
    setState(_cargarHijos);
  }

  int _calcularEdad(DateTime fechaNacimiento) {
    final ahora = DateTime.now();
    var edad = ahora.year - fechaNacimiento.year;
    if (ahora.month < fechaNacimiento.month ||
        (ahora.month == fechaNacimiento.month && ahora.day < fechaNacimiento.day)) {
      edad--;
    }
    return edad;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirAgregarHijo,
        icon: const Icon(Icons.add),
        label: const Text('Agregar hijo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Bienvenido, ${widget.usuario.nombre}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Nino>>(
              future: _hijosFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final hijos = snapshot.data ?? [];
                if (hijos.isEmpty) {
                  return const Center(child: Text('Todavía no tienes niños registrados.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                  itemCount: hijos.length,
                  itemBuilder: (context, i) {
                    final nino = hijos[i];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.amarillo,
                          child: Icon(Icons.child_care, color: AppColors.textoPrincipal),
                        ),
                        title: Text(nino.nombreCompleto),
                        subtitle: Text('${_calcularEdad(nino.fechaNacimiento)} años · ${nino.genero}'),
                        trailing: nino.alertaMedicaFlag
                            ? const Tooltip(
                                message: 'Tiene condición médica/alergia registrada',
                                child: Icon(Icons.medical_information, color: AppColors.rojo),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Se muestra cuando el usuario logueado (sin importar su rol) todavía
/// no tiene un perfil de acudiente. Al llenarlo, no crea otra cuenta —
/// solo agrega esa capacidad a la cuenta que ya tiene.
class _RegistroAcudienteForm extends StatefulWidget {
  final UsuarioApp usuario;
  final VoidCallback onListo;

  const _RegistroAcudienteForm({required this.usuario, required this.onListo});

  @override
  State<_RegistroAcudienteForm> createState() => _RegistroAcudienteFormState();
}

class _RegistroAcudienteFormState extends State<_RegistroAcudienteForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numeroDocumentoController;
  late final TextEditingController _nombresController;
  late final TextEditingController _apellidosController;
  final _telefonoController = TextEditingController();
  String? _tipoDocumento;
  Uint8List? _fotoBytes;
  String? _fotoExt;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _numeroDocumentoController = TextEditingController();
    _nombresController = TextEditingController(text: widget.usuario.nombre);
    _apellidosController = TextEditingController(text: widget.usuario.apellido);
  }

  @override
  void dispose() {
    _numeroDocumentoController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
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

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await AuthService().crearPerfilAcudiente(
        acudiente: Acudiente(
          uid: '',
          tipoDocumento: _tipoDocumento!,
          numeroDocumento: _numeroDocumentoController.text.trim(),
          nombres: _nombresController.text.trim(),
          apellidos: _apellidosController.text.trim(),
          telefonoCelular: _telefonoController.text.trim(),
          correoElectronico: widget.usuario.correo,
        ),
        fotoBytes: _fotoBytes,
        fotoExt: _fotoExt,
      );
      widget.onListo();
    } on AuthException catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String? _requerido(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                  Text('Regístrate como acudiente', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Con esto puedes registrar o vincular niños bajo tu misma cuenta, '
                    'sin perder tu rol actual.',
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _elegirFoto,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
                            backgroundImage:
                                _fotoBytes != null ? MemoryImage(_fotoBytes!) : null,
                            child: _fotoBytes == null
                                ? const Icon(Icons.add_a_photo, size: 28)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fotoBytes == null ? 'Foto de seguridad (opcional)' : 'Toca para cambiarla',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
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
                    keyboardType: TextInputType.number,
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
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: AppColors.rojo), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _cargando ? null : _guardar,
                    child: _cargando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Continuar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

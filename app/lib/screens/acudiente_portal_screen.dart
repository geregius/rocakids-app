import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/foto_picker.dart';
import '../widgets/app_shell.dart';
import 'agregar_hijo_screen.dart';
import 'nino_detalle_sheet.dart';

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
  // Se lanza EN PARALELO con _acudienteFuture desde el inicio, no después
  // de que ese resuelva — ambas consultas son independientes (dependen
  // solo del uid de la sesión), así que esperarlas una tras otra sumaba
  // un viaje de red completo sin necesidad antes de mostrar la lista.
  late Future<List<Nino>> _hijosFuture;
  final _listaKey = GlobalKey<_ListaDeHijosState>();

  @override
  void initState() {
    super.initState();
    _acudienteFuture = AuthService().obtenerMiAcudiente();
    _hijosFuture = AuthService().obtenerMisHijos();
  }

  void _recargar() => setState(() {
    _acudienteFuture = AuthService().obtenerMiAcudiente();
    _hijosFuture = AuthService().obtenerMisHijos();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Acudiente?>(
      future: _acudienteFuture,
      builder: (context, snapshot) {
        final cargando = snapshot.connectionState == ConnectionState.waiting;
        final tieneAcudiente = !cargando && !snapshot.hasError && snapshot.data != null;

        Widget body;
        if (cargando) {
          body = const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          body = Center(child: Text('Error: ${snapshot.error}'));
        } else if (!tieneAcudiente) {
          body = _SinPerfilAcudiente(usuario: widget.usuario, onListo: _recargar);
        } else {
          body = _ListaDeHijos(
            key: _listaKey,
            usuario: widget.usuario,
            hijosInicialFuture: _hijosFuture,
          );
        }

        return AppShell(
          usuario: widget.usuario,
          seccionActiva: 'Mis hijos',
          floatingActionButton: tieneAcudiente
              ? FloatingActionButton.extended(
                  onPressed: () => _listaKey.currentState?.abrirAgregarHijo(),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar hijo'),
                )
              : null,
          body: (context) => body,
        );
      },
    );
  }
}

class _ListaDeHijos extends StatefulWidget {
  final UsuarioApp usuario;
  // Future ya en vuelo desde el padre (lanzada en paralelo con la
  // consulta del perfil de acudiente) — se usa solo la primera vez, para
  // no repetir esa consulta; una recarga posterior (agregar hijo, etc.)
  // sí pide una nueva.
  final Future<List<Nino>> hijosInicialFuture;
  const _ListaDeHijos({super.key, required this.usuario, required this.hijosInicialFuture});

  @override
  State<_ListaDeHijos> createState() => _ListaDeHijosState();
}

class _ListaDeHijosState extends State<_ListaDeHijos> {
  late Future<List<Nino>> _hijosFuture;

  @override
  void initState() {
    super.initState();
    _hijosFuture = widget.hijosInicialFuture;
  }

  void _cargarHijos() {
    _hijosFuture = AuthService().obtenerMisHijos();
  }

  Future<void> abrirAgregarHijo() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AgregarHijoScreen()),
    );
    setState(_cargarHijos);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                      onTap: () async {
                        final cambio = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => NinoDetalleSheet(nino: nino, usuario: widget.usuario),
                        );
                        if (cambio == true) setState(_cargarHijos);
                      },
                      leading: CircleAvatar(
                        backgroundColor: AppColors.amarillo,
                        backgroundImage:
                            nino.fotoUrl.isNotEmpty ? NetworkImage(nino.fotoUrl) : null,
                        child: nino.fotoUrl.isEmpty
                            ? const Icon(Icons.child_care, color: AppColors.textoPrincipal)
                            : null,
                      ),
                      title: Text(nino.nombreCompleto),
                      subtitle: Text(
                        '${calcularEdad(nino.fechaNacimiento)} años · '
                        '${nino.identificacionMenor.isNotEmpty ? nino.identificacionMenor : 'Sin documento'}',
                      ),
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
    );
  }
}

/// Se muestra cuando el usuario logueado (sin importar su rol) todavía
/// no tiene un perfil de acudiente. Si ya tiene un perfil de servidor
/// completo, ofrece reutilizar esos datos (documento, teléfono, foto) en
/// vez de pedírselos de nuevo; si no los tiene, o prefiere otros datos,
/// cae al formulario completo.
class _SinPerfilAcudiente extends StatefulWidget {
  final UsuarioApp usuario;
  final VoidCallback onListo;

  const _SinPerfilAcudiente({required this.usuario, required this.onListo});

  @override
  State<_SinPerfilAcudiente> createState() => _SinPerfilAcudienteState();
}

class _SinPerfilAcudienteState extends State<_SinPerfilAcudiente> {
  bool _usarFormularioManual = false;

  @override
  Widget build(BuildContext context) {
    final puedeReutilizarDatos =
        widget.usuario.rol.esRolDeServidor && widget.usuario.perfilCompleto;

    if (puedeReutilizarDatos && !_usarFormularioManual) {
      return _ReutilizarDatosServidor(
        usuario: widget.usuario,
        onListo: widget.onListo,
        onPrefiereOtrosDatos: () => setState(() => _usarFormularioManual = true),
      );
    }
    return _RegistroAcudienteForm(usuario: widget.usuario, onListo: widget.onListo);
  }
}

/// Resumen de los datos que el usuario ya tiene como servidor, con la
/// opción de reutilizarlos como perfil de acudiente en un solo toque —
/// sin volver a escribir nada ni volver a subir la foto (se reutiliza la
/// misma URL de Storage).
class _ReutilizarDatosServidor extends StatefulWidget {
  final UsuarioApp usuario;
  final VoidCallback onListo;
  final VoidCallback onPrefiereOtrosDatos;

  const _ReutilizarDatosServidor({
    required this.usuario,
    required this.onListo,
    required this.onPrefiereOtrosDatos,
  });

  @override
  State<_ReutilizarDatosServidor> createState() => _ReutilizarDatosServidorState();
}

class _ReutilizarDatosServidorState extends State<_ReutilizarDatosServidor> {
  bool _cargando = false;
  String? _error;

  Future<void> _usarEstosDatos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await AuthService().crearPerfilAcudienteDesdeServidor(widget.usuario);
      widget.onListo();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo completar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = widget.usuario;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Regístrate como acudiente', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Ya tenemos tus datos como servidor. Podemos usarlos también '
                  'como acudiente, sin pedírtelos de nuevo ni repetir la foto.',
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
                          backgroundImage:
                              usuario.fotoUrl.isNotEmpty ? NetworkImage(usuario.fotoUrl) : null,
                          child: usuario.fotoUrl.isEmpty ? const Icon(Icons.person) : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                usuario.nombreCompleto,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text('${usuario.tipoDocumento}: ${usuario.numeroDocumento}'),
                              Text(usuario.telefono),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.rojo), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _cargando ? null : _usarEstosDatos,
                  child: _cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Usar estos datos y continuar'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _cargando ? null : widget.onPrefiereOtrosDatos,
                  child: const Text('Prefiero ingresar otros datos'),
                ),
              ],
            ),
          ),
        ),
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
    final foto = await elegirFotoConCamaraOGaleria(context);
    if (foto == null) return;
    setState(() {
      _fotoBytes = foto.bytes;
      _fotoExt = foto.extension;
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
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo completar el perfil: $e');
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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/foto_picker.dart';
import '../utils/selector_fecha_nacimiento.dart';

/// Auto-registro de un Acudiente junto con uno o varios niños. A
/// diferencia del registro de servidor, aquí el acceso es inmediato —
/// no requiere aprobación de un administrador.
///
/// Wizard de 3 pasos con transición deslizante (`PageView`, 2026-08-21,
/// mismo patrón que "Registrar familia"): 1) datos del acudiente, 2)
/// uno o varios niños (cada uno con su propio parentesco), 3) resumen
/// en tarjetas. A propósito NO tiene búsqueda de acudiente/niño ya
/// existente (a diferencia de "Registrar familia"): quien llena esto
/// TODAVÍA no tiene sesión, y `ninos_busqueda`/`acudientes_documentos`
/// exigen estar autenticado para poder leerse (ver firestore.rules) —
/// siempre crea una cuenta y niños nuevos.
class SignUpAcudienteScreen extends StatefulWidget {
  const SignUpAcudienteScreen({super.key});

  @override
  State<SignUpAcudienteScreen> createState() => _SignUpAcudienteScreenState();
}

/// Datos de un niño dentro del wizard — cada tarjeta de "Registro del o
/// los menores" tiene su propia instancia y sus propios controladores.
class _MenorFormData {
  final identificacionMenorController = TextEditingController();
  final nombresController = TextEditingController();
  final apellidosController = TextEditingController();
  final condicionMedicaController = TextEditingController();
  String? tipoIdentificacionMenor;
  String? genero;
  String? parentesco;
  DateTime? fechaNacimiento;
  bool autorizaFoto = false;
  bool tieneCondicionMedica = false;
  Uint8List? fotoBytes;
  String? fotoExt;

  void dispose() {
    identificacionMenorController.dispose();
    nombresController.dispose();
    apellidosController.dispose();
    condicionMedicaController.dispose();
  }
}

class _SignUpAcudienteScreenState extends State<SignUpAcudienteScreen> {
  final _authService = AuthService();
  final _pageController = PageController();
  int _currentStep = 0;

  // Paso 1 — acudiente.
  final _formKeyAcudiente = GlobalKey<FormState>();
  final _numeroDocumentoController = TextEditingController();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _tipoDocumento;
  bool _mostrarPassword = false;
  Uint8List? _fotoAcudienteBytes;
  String? _fotoAcudienteExt;

  // Paso 2 — uno o varios niños.
  final List<_MenorFormData> _menores = [_MenorFormData()];

  bool _cargando = false;
  String? _error;
  bool _registroExitoso = false;

  @override
  void dispose() {
    _numeroDocumentoController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    for (final m in _menores) {
      m.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  // ---- Navegación entre pasos ----

  void _irAPaso(int paso) {
    _pageController.animateToPage(
      paso,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  void _siguientePaso() {
    if (_currentStep == 0) {
      if (!_formKeyAcudiente.currentState!.validate()) return;
    } else if (_currentStep == 1) {
      final error = _validarMenores();
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }
    setState(() => _error = null);
    _irAPaso(_currentStep + 1);
  }

  String? _validarMenores() {
    if (_menores.isEmpty) return 'Agrega al menos un niño.';
    for (var i = 0; i < _menores.length; i++) {
      final m = _menores[i];
      final n = i + 1;
      if (m.tipoIdentificacionMenor == null) {
        return 'Selecciona el tipo de documento del niño $n.';
      }
      // El número de documento NUNCA es obligatorio para registrar a un
      // niño (2026-08-24, pedido explícito de Rafael) — aunque se haya
      // elegido un tipo de documento real (no "No tiene documento"), se
      // puede dejar el número en blanco si no se tiene a la mano en el
      // momento.
      if (m.nombresController.text.trim().isEmpty ||
          m.apellidosController.text.trim().isEmpty) {
        return 'Completa el nombre del niño $n.';
      }
      if (m.fechaNacimiento == null) {
        return 'Selecciona la fecha de nacimiento del niño $n.';
      }
      if (grupoParaEdad(calcularEdad(m.fechaNacimiento!)) == null) {
        return 'RocaKids recibe niños de $edadMinimaRegistro a '
            '$edadMaximaRegistro años (niño $n).';
      }
      if (m.genero == null) return 'Selecciona el género del niño $n.';
      if (m.parentesco == null) return 'Selecciona tu parentesco con el niño $n.';
      if (m.tieneCondicionMedica &&
          m.condicionMedicaController.text.trim().isEmpty) {
        return 'Describe la condición médica del niño $n.';
      }
    }
    return null;
  }

  // ---- Acciones del paso 1 ----

  Future<void> _elegirFotoAcudiente() async {
    final foto = await elegirFotoConCamaraOGaleria(context);
    if (foto == null) return;
    setState(() {
      _fotoAcudienteBytes = foto.bytes;
      _fotoAcudienteExt = foto.extension;
    });
  }

  // ---- Acciones del paso 2 ----

  void _agregarMenor() => setState(() => _menores.add(_MenorFormData()));

  void _quitarMenor(_MenorFormData m) {
    setState(() {
      _menores.remove(m);
      m.dispose();
    });
  }

  Future<void> _elegirFotoMenor(_MenorFormData m) async {
    final foto = await elegirFotoConCamaraOGaleria(context);
    if (foto == null) return;
    setState(() {
      m.fotoBytes = foto.bytes;
      m.fotoExt = foto.extension;
    });
  }

  // ---- Envío ----

  Nino _construirNinoNuevo(_MenorFormData m) {
    final tieneDocumento =
        m.tipoIdentificacionMenor != 'No tiene documento' &&
        m.identificacionMenorController.text.trim().isNotEmpty;
    final documentoIdentificacion = tieneDocumento
        ? m.identificacionMenorController.text.trim().toUpperCase()
        : generarLlaveInterna(
            fechaNacimiento: m.fechaNacimiento!,
            nombres: m.nombresController.text,
            apellidos: m.apellidosController.text,
          );
    return Nino(
      documentoIdentificacion: documentoIdentificacion,
      tipoIdentificacion: m.tipoIdentificacionMenor!,
      identificacionMenor: tieneDocumento
          ? m.identificacionMenorController.text.trim()
          : '',
      nombres: m.nombresController.text.trim(),
      apellidos: m.apellidosController.text.trim(),
      fechaNacimiento: m.fechaNacimiento!,
      genero: m.genero!,
      estadoRegistro: 'Activo',
      alertaMedicaFlag: m.tieneCondicionMedica,
      condicionMedica: m.tieneCondicionMedica
          ? m.condicionMedicaController.text.trim()
          : '',
      autorizoFotoFlag: m.autorizaFoto,
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
    if (!_formKeyAcudiente.currentState!.validate()) {
      _irAPaso(0);
      return;
    }
    final errorMenores = _validarMenores();
    if (errorMenores != null) {
      setState(() => _error = errorMenores);
      _irAPaso(1);
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final acudienteUid = await _authService.crearAcudienteNuevo(
        correo: _correoController.text,
        password: _passwordController.text,
        acudiente: _construirAcudienteNuevo(),
        fotoAcudienteBytes: _fotoAcudienteBytes,
        fotoAcudienteExt: _fotoAcudienteExt,
      );

      // En paralelo (2026-08-24, pedido de Rafael: "optimiza para que no
      // sea tan demorado") — antes cada niño esperaba a que el anterior
      // terminara por completo (su propia subida de foto + escritura en
      // Firestore). Cada niño escribe en SUS PROPIOS documentos, nunca
      // el mismo que otro niño de la misma familia, así que no hay
      // ningún riesgo de que se pisen entre sí corriendo a la vez.
      await Future.wait(
        _menores.map((m) {
          final nino = _construirNinoNuevo(m);
          return _authService.registrarNinoAdicional(
            nino: nino,
            parentescoTipo: m.parentesco!,
            acudienteUid: acudienteUid,
            fotoNinoBytes: m.fotoBytes,
            fotoNinoExt: m.fotoExt,
          );
        }),
      );

      // Ya existe sesión y perfil completos — el AuthGate (montado
      // debajo de esta pantalla desde que se abrió con Navigator.push)
      // ya está listo para mostrar el portal en cuanto se vuelva a él.
      if (mounted) {
        setState(() {
          _cargando = false;
          _registroExitoso = true;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.mensaje;
          _cargando = false;
        });
      }
    } catch (e) {
      // Antes SOLO se atrapaba `AuthException` — cualquier otro error
      // (de red, de Storage, un `FirebaseException` crudo) dejaba
      // `_cargando` en `true` PARA SIEMPRE: el botón seguía mostrando
      // el spinner sin ningún mensaje y sin volver a responder. Este
      // era el bug real detrás de "queda ahí bloqueado, no dice nada y
      // no hace nada" (2026-08-24, reportado por Rafael).
      if (mounted) {
        setState(() {
          _error = 'No se pudo completar el registro: $e';
          _cargando = false;
        });
      }
    }
  }

  String? _requerido(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de Acudiente')),
      body: Stack(
        children: [
          _registroExitoso
              ? _buildExito(context)
              : Column(
                  children: [
                    _buildEncabezadoPasos(context),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (i) => setState(() => _currentStep = i),
                        children: [
                          _buildPasoAcudiente(context),
                          _buildPasoMenores(context),
                          _buildPasoResumen(context),
                        ],
                      ),
                    ),
                    _buildBarraNavegacion(context),
                  ],
                ),
          // Overlay bien visible mientras se guarda (2026-08-24, pedido
          // de Rafael: "que aparezca algo de que se está realizando el
          // registro, por favor espere") — cubre toda la pantalla y
          // bloquea cualquier toque de doble envío.
          if (_cargando)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Registrando, por favor espera...',
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExito(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.azulMarino, size: 56),
            const SizedBox(height: 16),
            Text(
              '¡Bienvenido a RocaKids!',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tu cuenta y tus niños ya quedaron registrados.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Ir a Mis hijos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncabezadoPasos(BuildContext context) {
    const titulos = ['Tus datos', 'Registro del o los menores', 'Resumen'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (i) {
              final activo = i <= _currentStep;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: activo
                        ? AppColors.azulMarino
                        : AppColors.azulMarino.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Paso ${_currentStep + 1} de 3 · ${titulos[_currentStep]}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildBarraNavegacion(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Row(
          children: [
            if (_currentStep > 0)
              TextButton.icon(
                onPressed: _cargando ? null : () => _irAPaso(_currentStep - 1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Atrás'),
              ),
            const Spacer(),
            ElevatedButton(
              onPressed: _cargando ? null : (_currentStep < 2 ? _siguientePaso : _registrar),
              child: _cargando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_currentStep < 2 ? 'Siguiente' : 'Registrarme'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Paso 1 ----

  Widget _buildPasoAcudiente(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKeyAcudiente,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _elegirFotoAcudiente,
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _correoController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo electrónico'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
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
                    suffixIcon: IconButton(
                      icon: Icon(
                        _mostrarPassword ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.azulMarino,
                      ),
                      tooltip: _mostrarPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                      onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Ingresa una contraseña';
                    if (v.length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Paso 2 ----

  Widget _buildPasoMenores(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Agrega a tu(s) niño(s). Puedes agregar más de uno si son hermanos.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.rojo)),
              ],
              const SizedBox(height: 16),
              for (var i = 0; i < _menores.length; i++) ...[
                _buildTarjetaMenor(context, _menores[i], i),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                onPressed: _agregarMenor,
                icon: const Icon(Icons.add),
                label: const Text('Agregar otro niño'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTarjetaMenor(BuildContext context, _MenorFormData m, int index) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Niño ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_menores.length > 1)
                  IconButton(
                    onPressed: () => _quitarMenor(m),
                    icon: const Icon(Icons.delete_outline, color: AppColors.rojo),
                    tooltip: 'Quitar niño',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => _elegirFotoMenor(m),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.amarillo.withValues(alpha: 0.3),
                      backgroundImage: m.fotoBytes != null ? MemoryImage(m.fotoBytes!) : null,
                      child: m.fotoBytes == null
                          ? const Icon(Icons.add_a_photo, size: 28)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.fotoBytes == null ? 'Foto del niño (opcional)' : 'Toca para cambiarla',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: m.tipoIdentificacionMenor,
              decoration: const InputDecoration(labelText: 'Tipo de documento del niño'),
              items: tiposIdentificacionMenor
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => m.tipoIdentificacionMenor = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: m.identificacionMenorController,
              decoration: const InputDecoration(
                labelText: 'Número de documento del niño (opcional)',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: m.nombresController,
              decoration: const InputDecoration(labelText: 'Nombres del niño'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: m.apellidosController,
              decoration: const InputDecoration(labelText: 'Apellidos del niño'),
            ),
            const SizedBox(height: 16),
            SelectorFechaNacimiento(
              value: m.fechaNacimiento,
              onChanged: (v) => setState(() => m.fechaNacimiento = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: m.genero,
              decoration: const InputDecoration(labelText: 'Género'),
              items: generos.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
              onChanged: (v) => setState(() => m.genero = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: m.parentesco,
              decoration: const InputDecoration(labelText: 'Tu parentesco con el niño'),
              items: parentescos.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => m.parentesco = v),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('¿Autoriza el uso de imagen del niño?'),
              value: m.autorizaFoto,
              onChanged: (v) => setState(() => m.autorizaFoto = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('¿Presenta alguna condición médica o alergia?'),
              value: m.tieneCondicionMedica,
              onChanged: (v) => setState(() => m.tieneCondicionMedica = v ?? false),
            ),
            if (m.tieneCondicionMedica) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: m.condicionMedicaController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Detalle de la condición médica / alergia',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- Paso 3 ----

  Widget _buildPasoResumen(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Revisa tus datos antes de confirmar.'),
              const SizedBox(height: 16),
              Text('Tú (acudiente)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildResumenAcudiente(context),
              const SizedBox(height: 20),
              Text(
                _menores.length > 1 ? 'Niños' : 'Niño',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _menores.length; i++) ...[
                _buildResumenMenor(context, _menores[i], i),
                const SizedBox(height: 8),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.rojo),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumenAcudiente(BuildContext context) {
    final nombre = '${_nombresController.text} ${_apellidosController.text}'.trim();
    return Card(
      color: AppColors.azulClaro.withValues(alpha: 0.1),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.azulClaro.withValues(alpha: 0.3),
          backgroundImage: _fotoAcudienteBytes != null ? MemoryImage(_fotoAcudienteBytes!) : null,
          child: _fotoAcudienteBytes == null ? const Icon(Icons.person) : null,
        ),
        title: Text(nombre.isEmpty ? '—' : nombre),
        subtitle: Text('${_tipoDocumento ?? ''}: ${_numeroDocumentoController.text}'),
        trailing: TextButton(onPressed: () => _irAPaso(0), child: const Text('Editar')),
      ),
    );
  }

  Widget _buildResumenMenor(BuildContext context, _MenorFormData m, int index) {
    final nombre = '${m.nombresController.text} ${m.apellidosController.text}'.trim();
    final edadTxt = m.fechaNacimiento != null ? '${calcularEdad(m.fechaNacimiento!)} años' : '';
    return Card(
      color: AppColors.amarillo.withValues(alpha: 0.08),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.amarillo.withValues(alpha: 0.3),
          backgroundImage: m.fotoBytes != null ? MemoryImage(m.fotoBytes!) : null,
          child: m.fotoBytes == null ? const Icon(Icons.child_care) : null,
        ),
        title: Text(nombre.isEmpty ? 'Niño ${index + 1}' : nombre),
        subtitle: Text('$edadTxt · Parentesco: ${m.parentesco ?? "—"}'),
        trailing: TextButton(onPressed: () => _irAPaso(1), child: const Text('Editar')),
      ),
    );
  }
}

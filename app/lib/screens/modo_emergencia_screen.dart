import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
import '../models/registro.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/foto_picker.dart';
import '../utils/reporte_emergencia_pdf.dart';
import '../widgets/firma_pad.dart';
import '../widgets/foto_avatar.dart';

const _sinGrupo = 'Sin grupo';

/// Contenido de "Modo emergencia" (2026-08-19, pedido de Rafael): control
/// extra de seguridad para una evacuación u otra emergencia real, donde
/// puede que quien retira a un niño no sea la persona de siempre.
///
/// A propósito NO trae su propio `Scaffold`/menú — dos contextos muy
/// distintos lo envuelven:
/// - Navegación normal (leadership, mientras la emergencia está
///   inactiva): `AppShell` completo, con el menú de siempre — ver el
///   ítem "Modo emergencia" en `widgets/app_shell.dart`.
/// - Bloqueo global (emergencia ACTIVA, ver
///   `AuthService.emergenciaActivaStream()`): `AppShell` reemplaza TODO
///   su contenido por esto, sin menú lateral, para cualquier servidor —
///   ver la rama de bloqueo en `AppShell.build()`.
///
/// Cualquier servidor (sin importar su rol) puede ver el listado y dar
/// salida a un niño desde acá; los controles de activar/desactivar y de
/// generar el reporte PDF quedan solo para
/// `usuario.rol.puedeActivarModoEmergencia` (administrador, columna,
/// líder de ministerio).
class ModoEmergenciaBody extends StatefulWidget {
  final UsuarioApp usuario;
  const ModoEmergenciaBody({super.key, required this.usuario});

  @override
  State<ModoEmergenciaBody> createState() => _ModoEmergenciaBodyState();
}

class _ModoEmergenciaBodyState extends State<ModoEmergenciaBody> {
  final _authService = AuthService();
  final Map<String, Nino> _ninosPorId = {};
  final Set<String> _pidiendo = {};
  final Set<String> _ocultosOptimista = {};
  bool _generandoReporte = false;

  bool get _puedeControlar => widget.usuario.rol.puedeActivarModoEmergencia;

  void _asegurarNinosCargados(Iterable<String> ids) {
    final faltantes = ids
        .where((id) => !_ninosPorId.containsKey(id) && !_pidiendo.contains(id))
        .toSet();
    if (faltantes.isEmpty) return;
    _pidiendo.addAll(faltantes);
    _authService.obtenerNinosPorIds(faltantes).then((ninos) {
      if (!mounted) return;
      setState(() {
        for (final n in ninos) {
          _ninosPorId[n.documentoIdentificacion] = n;
        }
        _pidiendo.removeAll(faltantes);
      });
    });
  }

  Future<void> _activar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Activar modo emergencia?'),
        content: const Text(
          'Todos los servidores conectados quedarán restringidos SOLO al '
          'listado de menores presentes, y los acudientes perderán acceso '
          'a "Mis hijos" hasta que se desactive. Úsalo solo ante una '
          'emergencia real.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rojo),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    try {
      await _authService.activarModoEmergencia(widget.usuario.nombreCompleto);
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    }
  }

  Future<void> _desactivar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desactivar modo emergencia?'),
        content: const Text(
          'La app vuelve a funcionar normal para todos. Recuerda generar '
          'el reporte antes si todavía no lo has hecho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    try {
      await _authService.desactivarModoEmergencia();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    }
  }

  Future<void> _generarReporte() async {
    setState(() => _generandoReporte = true);
    try {
      final registrosHoy = await _authService.registrosDeHoy().first;
      if (mounted) await generarReporteEmergenciaPdf(registrosHoy);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el reporte: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoReporte = false);
    }
  }

  Future<void> _abrirSalidaEmergencia(Registro entrada) async {
    final nino = entrada.esVisitante ? null : _ninosPorId[entrada.fkIdNino];
    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SalidaEmergenciaSheet(
        entrada: entrada,
        nino: nino,
        usuario: widget.usuario,
      ),
    );
    if (resultado == true && mounted) {
      setState(() => _ocultosOptimista.add(entrada.id));
    }
  }

  Map<String, List<Registro>> _agruparPorEdad(List<Registro> presentes) {
    final grupos = <String, List<Registro>>{};
    for (final r in presentes) {
      final grupo = gruposEdad.contains(r.grupoEdad) ? r.grupoEdad : _sinGrupo;
      grupos.putIfAbsent(grupo, () => []).add(r);
    }
    for (final lista in grupos.values) {
      lista.sort(
        (a, b) => _nombreDe(a).toLowerCase().compareTo(_nombreDe(b).toLowerCase()),
      );
    }
    return grupos;
  }

  String _nombreDe(Registro r) => r.esVisitante
      ? r.nombreNinoVisitante
      : (_ninosPorId[r.fkIdNino]?.nombreCompleto ?? '(sin datos)');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _authService.emergenciaActivaStream(),
      builder: (context, snapEstado) {
        final activo = snapEstado.data ?? false;
        return Column(
          children: [
            _EncabezadoEstado(
              activo: activo,
              puedeControlar: _puedeControlar,
              generandoReporte: _generandoReporte,
              onActivar: _activar,
              onDesactivar: _desactivar,
              onGenerarReporte: _generarReporte,
            ),
            Expanded(
              child: StreamBuilder<List<Registro>>(
                stream: _authService.registrosDeHoy(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final presentes = calcularPresentes(snapshot.data ?? [])
                      .where((r) => !_ocultosOptimista.contains(r.id))
                      .toList();
                  _asegurarNinosCargados(
                    presentes.where((r) => !r.esVisitante).map((r) => r.fkIdNino),
                  );
                  final grupos = _agruparPorEdad(presentes);
                  final ordenados = [
                    ...gruposEdad,
                    if (grupos.containsKey(_sinGrupo)) _sinGrupo,
                  ];

                  if (presentes.isEmpty) {
                    return const Center(
                      child: Text('No hay niños presentes en este momento.'),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Presentes: ${presentes.length}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      for (final grupo in ordenados)
                        if (grupos[grupo] != null)
                          _GrupoSection(
                            key: ValueKey(grupo),
                            nombre: grupo,
                            registros: grupos[grupo]!,
                            ninosPorId: _ninosPorId,
                            onSeleccionar: _abrirSalidaEmergencia,
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EncabezadoEstado extends StatelessWidget {
  final bool activo;
  final bool puedeControlar;
  final bool generandoReporte;
  final VoidCallback onActivar;
  final VoidCallback onDesactivar;
  final VoidCallback onGenerarReporte;

  const _EncabezadoEstado({
    required this.activo,
    required this.puedeControlar,
    required this.generandoReporte,
    required this.onActivar,
    required this.onDesactivar,
    required this.onGenerarReporte,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: activo ? AppColors.rojo.withValues(alpha: 0.12) : AppColors.superficie,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                activo ? Icons.priority_high : Icons.check_circle,
                color: activo ? AppColors.rojo : AppColors.azulMarino,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activo ? 'Modo emergencia ACTIVO' : 'Modo emergencia inactivo',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: activo ? AppColors.rojo : AppColors.textoPrincipal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (!puedeControlar) ...[
            const SizedBox(height: 4),
            Text(
              activo
                  ? 'Toca un niño de la lista para darle salida de emergencia.'
                  : 'No hay ninguna emergencia activa en este momento.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (puedeControlar) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!activo)
                  ElevatedButton.icon(
                    onPressed: onActivar,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.rojo),
                    icon: const Icon(Icons.priority_high),
                    label: const Text('Activar modo emergencia'),
                  ),
                if (activo)
                  OutlinedButton.icon(
                    onPressed: onDesactivar,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Desactivar modo emergencia'),
                  ),
                OutlinedButton.icon(
                  onPressed: generandoReporte ? null : onGenerarReporte,
                  icon: generandoReporte
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text('Generar reporte PDF (hoy)'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GrupoSection extends StatelessWidget {
  final String nombre;
  final List<Registro> registros;
  final Map<String, Nino> ninosPorId;
  final ValueChanged<Registro> onSeleccionar;

  const _GrupoSection({
    super.key,
    required this.nombre,
    required this.registros,
    required this.ninosPorId,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    final rangoEdad = rangoEdadPorGrupo[nombre];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              rangoEdad != null
                  ? 'Grupo $nombre · $rangoEdad (${registros.length})'
                  : 'Grupo $nombre (${registros.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.azulMarino,
                fontWeight: FontWeight.bold,
              ),
            ),
            children: [
              const Divider(height: 1),
              for (final r in registros)
                _NinoPresenteTile(
                  registro: r,
                  nino: r.esVisitante ? null : ninosPorId[r.fkIdNino],
                  onTap: () => onSeleccionar(r),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NinoPresenteTile extends StatelessWidget {
  final Registro registro;
  final Nino? nino;
  final VoidCallback onTap;

  const _NinoPresenteTile({required this.registro, required this.nino, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nombre = registro.esVisitante
        ? registro.nombreNinoVisitante
        : (nino?.nombreCompleto ?? '(sin datos)');
    final tieneAlertaMedica =
        registro.esVisitante ? registro.alertaMedicaVisitante : (nino?.alertaMedicaFlag ?? false);

    return ListTile(
      onTap: onTap,
      leading: FotoAvatar(
        url: nino?.fotoUrl ?? '',
        iconoSinFoto: Icons.child_care,
        backgroundColor: AppColors.amarillo,
        iconColor: AppColors.textoPrincipal,
      ),
      title: Text(nombre),
      subtitle: Text('Manilla ${registro.numeroManilla}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tieneAlertaMedica)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.medical_information, color: AppColors.rojo),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// Formulario para dar salida a un niño durante la emergencia — exige,
/// además de elegir/escribir quién lo retira (mismo picker de
/// acudientes autorizados de siempre, con la advertencia de
/// "Restringido"), una foto tomada en el momento y una firma.
class _SalidaEmergenciaSheet extends StatefulWidget {
  final Registro entrada;
  final Nino? nino;
  final UsuarioApp usuario;

  const _SalidaEmergenciaSheet({
    required this.entrada,
    required this.nino,
    required this.usuario,
  });

  @override
  State<_SalidaEmergenciaSheet> createState() => _SalidaEmergenciaSheetState();
}

class _SalidaEmergenciaSheetState extends State<_SalidaEmergenciaSheet> {
  final _authService = AuthService();
  final _firmaKey = GlobalKey<FirmaPadState>();
  final _otroNombreController = TextEditingController();

  bool _cargandoAcudientes = true;
  List<Acudiente> _acudientes = [];
  Acudiente? _acudienteElegido;
  bool _otroAcudiente = false;

  Uint8List? _fotoBytes;
  String? _fotoExt;

  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarAcudientes();
  }

  @override
  void dispose() {
    _otroNombreController.dispose();
    super.dispose();
  }

  Future<void> _cargarAcudientes() async {
    if (widget.entrada.esVisitante) {
      setState(() => _cargandoAcudientes = false);
      return;
    }
    try {
      final acudientes = await _authService.obtenerAcudientesDeNino(widget.entrada.fkIdNino);
      if (mounted) {
        setState(() {
          _acudientes = acudientes;
          _cargandoAcudientes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoAcudientes = false);
    }
  }

  Future<void> _tomarFoto() async {
    final archivo = await tomarFotoConCamara();
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    setState(() {
      _fotoBytes = bytes;
      _fotoExt = archivo.name.contains('.') ? archivo.name.split('.').last : 'jpg';
    });
  }

  String get _nombreNino =>
      widget.entrada.esVisitante ? widget.entrada.nombreNinoVisitante : (widget.nino?.nombreCompleto ?? '(sin datos)');

  Future<void> _confirmar() async {
    final nombreContacto = _otroAcudiente
        ? _otroNombreController.text.trim()
        : (_acudienteElegido?.nombreCompleto ?? '');
    if (nombreContacto.isEmpty) {
      setState(() => _error = 'Indica quién retira al niño.');
      return;
    }
    if (_fotoBytes == null || _fotoExt == null) {
      setState(() => _error = 'Toma una foto de quien retira al niño.');
      return;
    }
    final firmaBytes = await _firmaKey.currentState?.exportarPng();
    if (firmaBytes == null) {
      setState(() => _error = 'Falta la firma de quien retira al niño.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    final salida = Registro(
      id: '',
      fkIdNino: widget.entrada.fkIdNino,
      nombreNinoVisitante: widget.entrada.nombreNinoVisitante,
      tipoMovimiento: 'Salida',
      fechaMovimiento: DateTime.now(),
      numeroManilla: widget.entrada.numeroManilla,
      fkIdServidor: '',
      nombreServidor: widget.usuario.nombreCompleto,
      fkIdAcudienteContacto: _otroAcudiente ? '' : (_acudienteElegido?.uid ?? ''),
      nombreAcudienteContacto: nombreContacto,
      servicio: widget.entrada.servicio,
      grupoEdad: widget.entrada.grupoEdad,
      observacion: 'Salida registrada durante Modo emergencia.',
      nombreAcudienteEntradaOriginal: widget.entrada.nombreAcudienteContacto,
    );

    try {
      await _authService.registrarSalidaEmergencia(
        salida: salida,
        fotoBytes: _fotoBytes!,
        fotoExt: _fotoExt!,
        firmaBytes: firmaBytes,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      setState(() {
        _error = e.mensaje;
        _guardando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo registrar la salida: $e';
        _guardando = false;
      });
    }
  }

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FotoAvatar(
                  url: widget.nino?.fotoUrl ?? '',
                  iconoSinFoto: Icons.child_care,
                  backgroundColor: AppColors.amarillo,
                  iconColor: AppColors.textoPrincipal,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_nombreNino, style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.superficie,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Según RocaKids, quien lo entregó fue: '
                '${widget.entrada.nombreAcudienteContacto.isNotEmpty ? widget.entrada.nombreAcudienteContacto : "(sin dato)"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 20),
            Text('¿Quién lo retira ahora?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (widget.entrada.esVisitante)
              TextFormField(
                controller: _otroNombreController,
                decoration: const InputDecoration(labelText: 'Nombre de quien retira'),
                onChanged: (_) => setState(() {}),
              )
            else if (_cargandoAcudientes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              RadioGroup<String>(
                groupValue: _otroAcudiente ? 'otro' : _acudienteElegido?.uid,
                onChanged: (v) => setState(() {
                  if (v == 'otro') {
                    _otroAcudiente = true;
                    _acudienteElegido = null;
                  } else {
                    _otroAcudiente = false;
                    _acudienteElegido = _acudientes.where((a) => a.uid == v).firstOrNull;
                  }
                }),
                child: Column(
                  children: [
                    ..._acudientes.map(
                      (a) => Card(
                        color: _acudienteElegido == a && !_otroAcudiente
                            ? AppColors.azulClaro.withValues(alpha: 0.15)
                            : null,
                        child: RadioListTile<String>(
                          value: a.uid,
                          secondary: FotoAvatar(url: a.fotoSeguridadUrl),
                          title: Text(a.nombreCompleto),
                          subtitle: a.estadoAutorizacion == 'Restringido'
                              ? Text(
                                  a.observacionesRestriccion.isNotEmpty
                                      ? 'RESTRINGIDO: ${a.observacionesRestriccion}'
                                      : 'RESTRINGIDO — no debería retirar al niño',
                                  style: const TextStyle(color: AppColors.rojo, fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                      ),
                    ),
                    Card(
                      child: RadioListTile<String>(
                        value: 'otro',
                        secondary: const Icon(Icons.person_outline),
                        title: const Text('Otro (no está en la lista)'),
                      ),
                    ),
                  ],
                ),
              ),
            if (_otroAcudiente || widget.entrada.esVisitante) ...[
              if (!widget.entrada.esVisitante) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _otroNombreController,
                  decoration: const InputDecoration(labelText: 'Nombre de quien retira'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
            const SizedBox(height: 20),
            Text('Foto de quien retira (obligatoria)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
                  backgroundImage: _fotoBytes != null ? MemoryImage(_fotoBytes!) : null,
                  child: _fotoBytes == null ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _tomarFoto,
                  icon: const Icon(Icons.photo_camera),
                  label: Text(_fotoBytes == null ? 'Tomar foto' : 'Tomar de nuevo'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FirmaPad(key: _firmaKey),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.rojo), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _guardando ? null : _confirmar,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.rojo),
              child: _guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Confirmar salida de emergencia'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../models/gestion.dart';
import '../models/nino.dart';
import '../models/no_autorizado.dart';
import '../models/registro.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/llamar_telefono.dart';
import '../widgets/confirmar_eliminar.dart';
import '../widgets/gestion_dialog.dart';
import 'editar_nino_sheet.dart';

/// Hoja inferior con la ficha completa de un niño: foto, documento, edad
/// y grupo actuales (calculados al momento, no guardados — ver
/// [grupoParaEdad]), y datos médicos/autorización si aplica. Si quien la
/// abre es el padre/madre vinculado (o un admin), puede editar la
/// información desde acá.
class NinoDetalleSheet extends StatefulWidget {
  final Nino nino;
  final UsuarioApp usuario;
  // La Entrada de HOY de este niño (`ninos_presentes_screen.dart`/
  // `cumpleanos_ninos_screen.dart`, 2026-08-24, pedido de Rafael) — solo
  // la pasan las pantallas que ya tienen esa información a mano. Se usa
  // para poner al acudiente que lo trajo primero en "Acudientes" y
  // marcarlo como "Lo trajo hoy" (`fkIdAcudienteContacto`), y para
  // mostrar/llamar al contacto "Otro (no está en la lista)" cuando no
  // fue un acudiente ya vinculado (`nombreAcudienteContacto`/
  // `telefonoAcudienteContacto`, sin `fkIdAcudienteContacto`). Queda
  // null desde cualquier otro punto de entrada (Mis hijos, Acudientes y
  // Niños, Dashboard) — ahí simplemente no hay nadie priorizado.
  final Registro? registroDeHoy;

  const NinoDetalleSheet({
    super.key,
    required this.nino,
    required this.usuario,
    this.registroDeHoy,
  });

  @override
  State<NinoDetalleSheet> createState() => _NinoDetalleSheetState();
}

class _NinoDetalleSheetState extends State<NinoDetalleSheet> {
  late Nino _nino;
  bool _cargandoPermiso = true;
  bool _puedeEditar = false;
  bool _eliminando = false;
  // Mi propia relación con este niño (si tengo una, de cualquier
  // parentesco) — se usa para el botón "Quitar de mis hijos". Distinto
  // de `_puedeEditar`, que solo es true si soy Padre/Madre.
  NinoAcudiente? _miRelacion;
  bool _desvinculando = false;

  // Personas NO autorizadas para tener contacto con este niño (custodias,
  // órdenes de alejamiento, etc.) — ver docstring de `NoAutorizado`.
  List<NoAutorizado> _noAutorizados = [];
  bool _cargandoNoAutorizados = true;
  bool _puedeGestionarNoAutorizados = false;
  bool _agregandoNoAutorizado = false;

  // Historial de gestión de asistencia (2026-08-21) — ver docstring de
  // `Gestion`. Solo liderazgo lo ve/gestiona, ni siquiera el padre/madre
  // (a diferencia de "no autorizados"): es seguimiento interno, no algo
  // que un acudiente necesite ver.
  List<Gestion> _gestiones = [];
  bool _cargandoGestiones = true;
  bool _esLiderazgo = false;
  bool _registrandoGestion = false;

  // Acudientes vinculados a este niño, con teléfono para poder llamar
  // directo (2026-08-24, pedido de Rafael). Solo se cargan/muestran para
  // roles de servidor (`esRolDeServidor`) — un acudiente viendo a su
  // propio hijo desde "Mis hijos" NO ve esta sección, para no exponerle
  // el teléfono de otros acudientes vinculados al mismo niño sin que lo
  // haya pedido.
  List<Acudiente> _acudientes = [];
  bool _cargandoAcudientes = true;

  bool get _esAdmin => widget.usuario.rol == RolUsuario.administrador;
  bool get _muestraAcudientes => widget.usuario.rol.esRolDeServidor;

  // true si hoy lo entregó/recibió alguien marcado como "Otro (no está
  // en la lista)" en vez de un acudiente ya vinculado — 2026-08-24,
  // pedido de Rafael: también poder llamar a esa persona desde acá.
  bool get _hayContactoOtroHoy {
    final registro = widget.registroDeHoy;
    return registro != null &&
        registro.fkIdAcudienteContacto.isEmpty &&
        registro.nombreAcudienteContacto.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _nino = widget.nino;
    _verificarPermiso();
    _cargarNoAutorizados();
    _cargarGestiones();
    if (_muestraAcudientes) {
      _cargarAcudientes();
    } else {
      _cargandoAcudientes = false;
    }
  }

  Future<void> _cargarAcudientes() async {
    try {
      final lista = await AuthService().obtenerAcudientesDeNino(
        _nino.documentoIdentificacion,
      );
      // El que lo trajo hoy va primero, para priorizarlo en la lista —
      // pedido explícito de Rafael.
      final acudienteQueLoTrajoHoyId = widget.registroDeHoy?.fkIdAcudienteContacto;
      lista.sort((a, b) {
        final aEsHoy = a.uid == acudienteQueLoTrajoHoyId;
        final bEsHoy = b.uid == acudienteQueLoTrajoHoyId;
        if (aEsHoy != bEsHoy) return aEsHoy ? -1 : 1;
        return a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase());
      });
      if (mounted) {
        setState(() {
          _acudientes = lista;
          _cargandoAcudientes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoAcudientes = false);
    }
  }

  Future<void> _verificarPermiso() async {
    final esAdmin = widget.usuario.rol == RolUsuario.administrador;
    final relacion = await AuthService().obtenerMiRelacionConNino(_nino.documentoIdentificacion);
    final esPadreOMadre =
        relacion?.parentescoTipo == 'Padre' || relacion?.parentescoTipo == 'Madre';
    final puedeEditar = esAdmin || esPadreOMadre;
    final esLiderazgo = esAdmin || widget.usuario.rol.puedeVerAcudientesYNinos;
    if (mounted) {
      setState(() {
        _puedeEditar = puedeEditar;
        _miRelacion = relacion;
        _cargandoPermiso = false;
        // Solo liderazgo o el padre/madre vinculado pueden agregar/quitar
        // personas no autorizadas — no cualquier servidor, por la
        // sensibilidad legal del dato (decisión de Rafael, 2026-08-21).
        _puedeGestionarNoAutorizados = esAdmin || esPadreOMadre || esLiderazgo;
        _esLiderazgo = esLiderazgo;
      });
    }
  }

  /// Mismo criterio que `_cargarNoAutorizados()`: si no hay permiso, la
  /// consulta falla con permission-denied y se trata como "no hay nada
  /// que mostrar", no como un error visible.
  Future<void> _cargarGestiones() async {
    try {
      final lista = await AuthService().obtenerGestiones(_nino.documentoIdentificacion);
      if (mounted) {
        setState(() {
          _gestiones = lista;
          _cargandoGestiones = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoGestiones = false);
    }
  }

  Future<void> _registrarGestion() async {
    final resultado = await mostrarDialogoGestion(
      context,
      nombreNino: _nino.nombreCompleto,
      estadoActual: _nino.estadoRegistro,
    );
    if (resultado == null) return;
    setState(() => _registrandoGestion = true);
    try {
      await AuthService().registrarGestion(
        ninoId: _nino.documentoIdentificacion,
        nota: resultado.nota,
        nuevoEstado: resultado.nuevoEstado,
        nombreRegistradoPor: widget.usuario.nombreCompleto,
      );
      final actualizado = await AuthService().obtenerNinoPorDocumento(
        _nino.documentoIdentificacion,
      );
      await _cargarGestiones();
      if (mounted) {
        setState(() {
          if (actualizado != null) _nino = actualizado;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gestión registrada.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _registrandoGestion = false);
    }
  }

  /// Si no tenemos permiso de lectura, la consulta falla con
  /// permission-denied — se trata igual que "no hay nada que mostrar",
  /// no como un error visible (quien abre la ficha sin ese permiso
  /// simplemente no ve esta sección).
  Future<void> _cargarNoAutorizados() async {
    try {
      final lista = await AuthService().obtenerNoAutorizados(_nino.documentoIdentificacion);
      if (mounted) {
        setState(() {
          _noAutorizados = lista;
          _cargandoNoAutorizados = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoNoAutorizados = false);
    }
  }

  Future<void> _agregarNoAutorizado() async {
    final resultado = await showDialog<_DatosNoAutorizado>(
      context: context,
      builder: (_) => const _AgregarNoAutorizadoDialog(),
    );
    if (resultado == null) return;
    setState(() => _agregandoNoAutorizado = true);
    try {
      await AuthService().agregarNoAutorizado(
        ninoId: _nino.documentoIdentificacion,
        nombre: resultado.nombre,
        documento: resultado.documento,
        motivo: resultado.motivo,
        nombreRegistradoPor: widget.usuario.nombreCompleto,
      );
      await _cargarNoAutorizados();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _agregandoNoAutorizado = false);
    }
  }

  Future<void> _quitarNoAutorizado(NoAutorizado entrada) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Quitar de la lista?'),
        content: Text(
          '${entrada.nombre} ya no va a aparecer como persona no autorizada '
          'para ${_nino.nombreCompleto}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rojo),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await AuthService().eliminarNoAutorizado(
        ninoId: _nino.documentoIdentificacion,
        entradaId: entrada.id,
      );
      await _cargarNoAutorizados();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo quitar: $e')));
      }
    }
  }

  Future<void> _abrirEdicion() async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditarNinoSheet(nino: _nino),
    );
    if (guardado == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _eliminar() async {
    final confirmado = await confirmarEliminar(context, nombre: _nino.nombreCompleto);
    if (!confirmado) return;
    setState(() => _eliminando = true);
    try {
      await AuthService().eliminarNino(_nino.documentoIdentificacion);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _eliminando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e')),
        );
      }
    }
  }

  /// Quita MI propio vínculo con este niño (ej. lo agregué por
  /// equivocación en "Mis hijos") — no borra al niño, solo la relación.
  /// No requiere ser Padre/Madre: cualquier parentesco puede
  /// deshacerse a sí mismo.
  Future<void> _desvincularme() async {
    final relacion = _miRelacion;
    if (relacion == null) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Quitar de mis hijos?'),
        content: Text(
          '${_nino.nombreCompleto} ya no va a aparecer en tu lista de "Mis '
          'hijos". Esto NO borra su información — solo quita tu vínculo con '
          'él/ella.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rojo),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    setState(() => _desvinculando = true);
    try {
      await AuthService().eliminarRelacionNinoAcudiente(
        ninoId: relacion.fkIdNino,
        acudienteUid: relacion.fkIdAcudiente,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _desvinculando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.mensaje)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _desvinculando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo quitar el vínculo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nino = _nino;
    final edad = calcularEdad(nino.fechaNacimiento);
    final grupo = grupoParaEdad(edad);

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
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.amarillo,
                  backgroundImage:
                      nino.fotoUrl.isNotEmpty ? NetworkImage(nino.fotoUrl) : null,
                  child: nino.fotoUrl.isEmpty
                      ? const Icon(Icons.child_care, color: AppColors.textoPrincipal)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nino.nombreCompleto, style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        grupo != null ? '$edad años · Grupo $grupo' : '$edad años',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FilaDato('Documento', '${nino.tipoIdentificacion}: '
                '${nino.identificacionMenor.isNotEmpty ? nino.identificacionMenor : 'Sin documento'}'),
            _FilaDato('Fecha de nacimiento', _formatearFecha(nino.fechaNacimiento)),
            _FilaDato('Género', nino.genero),
            _FilaDato('Estado', nino.estadoRegistro),
            _FilaDato('Autoriza uso de imagen', nino.autorizoFotoFlag ? 'Sí' : 'No'),
            if (_muestraAcudientes &&
                !_cargandoAcudientes &&
                (_acudientes.isNotEmpty || _hayContactoOtroHoy)) ...[
              const SizedBox(height: 12),
              _SeccionAcudientes(acudientes: _acudientes, registroDeHoy: widget.registroDeHoy),
            ],
            if (!nino.autorizoFotoFlag) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.rojo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.no_photography, color: AppColors.rojo),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'NO autoriza uso de imagen — no tomarle fotos ni videos.',
                        style: TextStyle(color: AppColors.rojo, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (nino.alertaMedicaFlag) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.rojo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.medical_information, color: AppColors.rojo),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nino.condicionMedica.isNotEmpty
                            ? nino.condicionMedica
                            : 'Tiene una condición médica/alergia registrada.',
                        style: const TextStyle(color: AppColors.rojo),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!_cargandoNoAutorizados && _noAutorizados.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SeccionNoAutorizados(
                entradas: _noAutorizados,
                puedeGestionar: _puedeGestionarNoAutorizados,
                onQuitar: _quitarNoAutorizado,
              ),
            ],
            if (!_cargandoPermiso && _puedeGestionarNoAutorizados) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _agregandoNoAutorizado ? null : _agregarNoAutorizado,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.rojo),
                icon: _agregandoNoAutorizado
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_off),
                label: const Text('Agregar persona NO autorizada'),
              ),
            ],
            if (_esLiderazgo && !_cargandoGestiones && _gestiones.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SeccionGestiones(gestiones: _gestiones),
            ],
            if (_esLiderazgo) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _registrandoGestion ? null : _registrarGestion,
                icon: _registrandoGestion
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined),
                label: const Text('Registrar gestión'),
              ),
            ],
            if (!_cargandoPermiso && _puedeEditar) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _abrirEdicion,
                icon: const Icon(Icons.edit),
                label: const Text('Editar información'),
              ),
            ],
            if (!_cargandoPermiso && _miRelacion != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _desvinculando ? null : _desvincularme,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.rojo),
                icon: _desvinculando
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: const Text('Quitar de mis hijos'),
              ),
            ],
            if (_esAdmin) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _eliminando ? null : _eliminar,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.rojo),
                icon: _eliminando
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: const Text('Eliminar niño'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatearFecha(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

/// Historial de gestión de asistencia — solo liderazgo lo ve (ver
/// docstring de `Gestion`), para evidenciar el seguimiento hecho a un
/// niño que dejó de asistir (o cualquier otro cambio de estado).
class _SeccionGestiones extends StatelessWidget {
  final List<Gestion> gestiones;
  const _SeccionGestiones({required this.gestiones});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.azulClaro.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.azulMarino),
              const SizedBox(width: 8),
              Text(
                'Historial de gestión',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          for (final g in gestiones) ...[
            const Divider(height: 16),
            Text(g.nota),
            Text(
              '${g.nombreRegistradoPor.isNotEmpty ? g.nombreRegistradoPor : 'alguien del equipo'} · '
              '${_formatearFecha(g.fecha)} · quedó ${g.estadoResultante}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Acudientes vinculados a este niño, con botón de llamar directo
/// (2026-08-24, pedido de Rafael). El que lo trajo hoy (si se conoce)
/// aparece primero y con una insignia. Si hoy lo trajo alguien marcado
/// como "Otro (no está en la lista)" en vez de un acudiente vinculado,
/// esa persona aparece primero de todos con su propio aviso — ver
/// docstring de `NinoDetalleSheet.registroDeHoy`.
class _SeccionAcudientes extends StatelessWidget {
  final List<Acudiente> acudientes;
  final Registro? registroDeHoy;

  const _SeccionAcudientes({required this.acudientes, required this.registroDeHoy});

  @override
  Widget build(BuildContext context) {
    final registro = registroDeHoy;
    final esOtro = registro != null &&
        registro.fkIdAcudienteContacto.isEmpty &&
        registro.nombreAcudienteContacto.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.azulClaro.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.family_restroom, color: AppColors.azulMarino),
              const SizedBox(width: 8),
              Text(
                'Acudientes',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (esOtro) ...[
            const Divider(height: 16),
            _FilaAcudiente(
              nombre: registro.nombreAcudienteContacto,
              telefono: registro.telefonoAcudienteContacto,
              loTrajoHoy: true,
              nota: 'No está vinculado en el sistema — registrado hoy como "Otro"',
            ),
          ],
          for (final a in acudientes) ...[
            const Divider(height: 16),
            _FilaAcudiente(
              nombre: a.nombreCompleto,
              telefono: a.telefonoCelular,
              loTrajoHoy: a.uid == registro?.fkIdAcudienteContacto,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaAcudiente extends StatelessWidget {
  final String nombre;
  final String telefono;
  final bool loTrajoHoy;
  final String? nota;

  const _FilaAcudiente({
    required this.nombre,
    required this.telefono,
    required this.loTrajoHoy,
    this.nota,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      nombre,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (loTrajoHoy) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.azulMarino,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Lo trajo hoy',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                telefono.isNotEmpty ? telefono : 'Sin teléfono registrado',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (nota != null)
                Text(
                  nota!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
        if (telefono.isNotEmpty)
          IconButton(
            onPressed: () => llamarTelefono(context, telefono),
            icon: const Icon(Icons.call, color: AppColors.azulMarino),
            tooltip: 'Llamar a $telefono',
          ),
      ],
    );
  }
}

class _FilaDato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _FilaDato(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}

/// Bloque rojo con la lista de personas NO autorizadas para tener
/// contacto con este niño — visible para cualquiera con permiso de
/// lectura (liderazgo, padre/madre, o quien hace check-in), pero solo
/// quien tiene [puedeGestionar] ve el botón de quitar cada entrada.
class _SeccionNoAutorizados extends StatelessWidget {
  final List<NoAutorizado> entradas;
  final bool puedeGestionar;
  final ValueChanged<NoAutorizado> onQuitar;

  const _SeccionNoAutorizados({
    required this.entradas,
    required this.puedeGestionar,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rojo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.rojo, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_off, color: AppColors.rojo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Personas NO autorizadas para retirar/tener contacto con este niño',
                  style: TextStyle(color: AppColors.rojo, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          for (final entrada in entradas) ...[
            const Divider(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entrada.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (entrada.documento.isNotEmpty)
                        Text('Documento: ${entrada.documento}'),
                      if (entrada.motivo.isNotEmpty) Text(entrada.motivo),
                      Text(
                        'Agregado por ${entrada.nombreRegistradoPor.isNotEmpty ? entrada.nombreRegistradoPor : 'alguien del equipo'} '
                        'el ${_formatearFecha(entrada.fechaRegistro)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (puedeGestionar)
                  IconButton(
                    onPressed: () => onQuitar(entrada),
                    icon: const Icon(Icons.delete_outline, color: AppColors.rojo),
                    tooltip: 'Quitar de la lista',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DatosNoAutorizado {
  final String nombre;
  final String documento;
  final String motivo;
  const _DatosNoAutorizado({
    required this.nombre,
    required this.documento,
    required this.motivo,
  });
}

class _AgregarNoAutorizadoDialog extends StatefulWidget {
  const _AgregarNoAutorizadoDialog();

  @override
  State<_AgregarNoAutorizadoDialog> createState() =>
      _AgregarNoAutorizadoDialogState();
}

class _AgregarNoAutorizadoDialogState extends State<_AgregarNoAutorizadoDialog> {
  final _nombreController = TextEditingController();
  final _documentoController = TextEditingController();
  final _motivoController = TextEditingController();

  @override
  void dispose() {
    _nombreController.dispose();
    _documentoController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  void _guardar() {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) return;
    Navigator.of(context).pop(
      _DatosNoAutorizado(
        nombre: nombre,
        documento: _documentoController.text.trim(),
        motivo: _motivoController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar persona NO autorizada'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Esta persona quedará marcada como NO autorizada para tener '
              'contacto con este niño. El aviso lo verá cualquiera que haga '
              'su check-in/check-out.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _documentoController,
              decoration: const InputDecoration(
                labelText: 'Documento (opcional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivoController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional, ej. "orden de alejamiento")',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardar,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.rojo),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

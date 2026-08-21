import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/no_autorizado.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/confirmar_eliminar.dart';
import 'editar_nino_sheet.dart';

/// Hoja inferior con la ficha completa de un niño: foto, documento, edad
/// y grupo actuales (calculados al momento, no guardados — ver
/// [grupoParaEdad]), y datos médicos/autorización si aplica. Si quien la
/// abre es el padre/madre vinculado (o un admin), puede editar la
/// información desde acá.
class NinoDetalleSheet extends StatefulWidget {
  final Nino nino;
  final UsuarioApp usuario;

  const NinoDetalleSheet({super.key, required this.nino, required this.usuario});

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

  bool get _esAdmin => widget.usuario.rol == RolUsuario.administrador;

  @override
  void initState() {
    super.initState();
    _nino = widget.nino;
    _verificarPermiso();
    _cargarNoAutorizados();
  }

  Future<void> _verificarPermiso() async {
    final esAdmin = widget.usuario.rol == RolUsuario.administrador;
    final relacion = await AuthService().obtenerMiRelacionConNino(_nino.documentoIdentificacion);
    final esPadreOMadre =
        relacion?.parentescoTipo == 'Padre' || relacion?.parentescoTipo == 'Madre';
    final puedeEditar = esAdmin || esPadreOMadre;
    if (mounted) {
      setState(() {
        _puedeEditar = puedeEditar;
        _miRelacion = relacion;
        _cargandoPermiso = false;
        // Solo liderazgo o el padre/madre vinculado pueden agregar/quitar
        // personas no autorizadas — no cualquier servidor, por la
        // sensibilidad legal del dato (decisión de Rafael, 2026-08-21).
        _puedeGestionarNoAutorizados =
            esAdmin || esPadreOMadre || widget.usuario.rol.puedeVerAcudientesYNinos;
      });
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

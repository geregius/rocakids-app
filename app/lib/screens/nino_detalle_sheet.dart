import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
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

  @override
  void initState() {
    super.initState();
    _nino = widget.nino;
    _verificarPermiso();
  }

  Future<void> _verificarPermiso() async {
    final esAdmin = widget.usuario.rol == RolUsuario.administrador;
    var puedeEditar = esAdmin;
    if (!puedeEditar) {
      final relacion = await AuthService().obtenerMiRelacionConNino(_nino.documentoIdentificacion);
      puedeEditar = relacion?.parentescoTipo == 'Padre' || relacion?.parentescoTipo == 'Madre';
    }
    if (mounted) {
      setState(() {
        _puedeEditar = puedeEditar;
        _cargandoPermiso = false;
      });
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
            if (!_cargandoPermiso && _puedeEditar) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _abrirEdicion,
                icon: const Icon(Icons.edit),
                label: const Text('Editar información'),
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

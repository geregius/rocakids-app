import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../theme/app_colors.dart';

/// Hoja inferior con la ficha completa de un niño: foto, documento, edad
/// y grupo actuales (calculados al momento, no guardados — ver
/// [grupoParaEdad]), y datos médicos/autorización si aplica.
class NinoDetalleSheet extends StatelessWidget {
  final Nino nino;

  const NinoDetalleSheet({super.key, required this.nino});

  @override
  Widget build(BuildContext context) {
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

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Diálogo de confirmación para una eliminación permanente — reusado
/// por las tres fichas (niño, acudiente, servidor) que solo el
/// administrador puede borrar (2026-08-18, pedido de Rafael). Devuelve
/// `true` solo si la persona tocó "Eliminar".
Future<bool> confirmarEliminar(
  BuildContext context, {
  required String nombre,
}) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Eliminar definitivamente?'),
      content: Text(
        '$nombre se va a eliminar de la base de datos. Esta acción no '
        'se puede deshacer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.rojo),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return confirmado ?? false;
}

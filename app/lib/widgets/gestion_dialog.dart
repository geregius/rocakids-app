import 'package:flutter/material.dart';

import '../models/nino.dart';

/// Resultado de [mostrarDialogoGestion]: la nota escrita y el estado
/// elegido para el niño (`estadosRegistroGestionables`).
class ResultadoGestion {
  final String nota;
  final String nuevoEstado;
  const ResultadoGestion({required this.nota, required this.nuevoEstado});
}

/// Diálogo compartido para registrar una gestión de seguimiento sobre
/// un niño (Dashboard → "Niños que dejaron de asistir", y la ficha del
/// niño) — pedido de Rafael (2026-08-21) para poder evidenciar que ese
/// reporte se está gestionando, no solo mirando. Devuelve `null` si se
/// cancela.
Future<ResultadoGestion?> mostrarDialogoGestion(
  BuildContext context, {
  required String nombreNino,
  required String estadoActual,
}) {
  return showDialog<ResultadoGestion>(
    context: context,
    builder: (_) => _GestionDialog(nombreNino: nombreNino, estadoActual: estadoActual),
  );
}

class _GestionDialog extends StatefulWidget {
  final String nombreNino;
  final String estadoActual;
  const _GestionDialog({required this.nombreNino, required this.estadoActual});

  @override
  State<_GestionDialog> createState() => _GestionDialogState();
}

class _GestionDialogState extends State<_GestionDialog> {
  final _notaController = TextEditingController();
  late String _estadoElegido;

  @override
  void initState() {
    super.initState();
    _estadoElegido = estadosRegistroGestionables.contains(widget.estadoActual)
        ? widget.estadoActual
        : 'Activo';
  }

  @override
  void dispose() {
    _notaController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (_notaController.text.trim().isEmpty) return;
    Navigator.of(context).pop(
      ResultadoGestion(nota: _notaController.text.trim(), nuevoEstado: _estadoElegido),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Registrar gestión — ${widget.nombreNino}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _notaController,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Qué se hizo / se supo',
                hintText: 'Ej. "Se llamó a la mamá, dice que se mudaron de ciudad"',
              ),
            ),
            const SizedBox(height: 16),
            const Text('¿Cómo queda el niño?', style: TextStyle(fontWeight: FontWeight.w600)),
            RadioGroup<String>(
              groupValue: _estadoElegido,
              onChanged: (v) => setState(() => _estadoElegido = v ?? _estadoElegido),
              child: Column(
                children: const [
                  RadioListTile<String>(
                    value: 'Activo',
                    contentPadding: EdgeInsets.zero,
                    title: Text('Sigue activo'),
                    subtitle: Text('Solo queda la nota — puede seguir apareciendo en el reporte.'),
                  ),
                  RadioListTile<String>(
                    value: 'Inactivo',
                    contentPadding: EdgeInsets.zero,
                    title: Text('Marcar inactivo'),
                    subtitle: Text('Ya no va a volver (ej. se mudó) — sale del reporte.'),
                  ),
                ],
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
        ElevatedButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

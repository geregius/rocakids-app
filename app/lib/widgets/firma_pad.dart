import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_colors.dart';

/// Lienzo para capturar una firma dibujada con el dedo/mouse — usado en
/// "Modo emergencia" (2026-08-19, pedido de Rafael) para exigir la firma
/// de quien retira a un niño durante una emergencia. A propósito sin
/// depender de ningún paquete nuevo: dibuja los trazos con un
/// `CustomPainter` y los exporta a PNG con `RenderRepaintBoundary`.
class FirmaPad extends StatefulWidget {
  const FirmaPad({super.key});

  @override
  State<FirmaPad> createState() => FirmaPadState();
}

class FirmaPadState extends State<FirmaPad> {
  final _repaintKey = GlobalKey();
  final List<List<Offset>> _trazos = [];

  bool get tieneFirma => _trazos.isNotEmpty;

  void limpiar() => setState(_trazos.clear);

  void _onPanStart(DragStartDetails d) {
    setState(() => _trazos.add([d.localPosition]));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _trazos.last.add(d.localPosition));
  }

  /// La firma como PNG, o `null` si todavía no se ha dibujado nada.
  Future<Uint8List?> exportarPng() async {
    if (_trazos.isEmpty) return null;
    final boundary =
        _repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final imagen = await boundary.toImage(pixelRatio: 2);
    final byteData = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.azulClaro.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: RepaintBoundary(
              key: _repaintKey,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.white,
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  child: CustomPaint(
                    painter: _FirmaPainter(_trazos),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Firma de quien retira al niño',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _trazos.isEmpty ? null : limpiar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Limpiar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FirmaPainter extends CustomPainter {
  final List<List<Offset>> trazos;
  const _FirmaPainter(this.trazos);

  @override
  void paint(Canvas canvas, Size size) {
    final pintura = Paint()
      ..color = AppColors.azulMarino
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final trazo in trazos) {
      for (var i = 0; i < trazo.length - 1; i++) {
        canvas.drawLine(trazo[i], trazo[i + 1], pintura);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FirmaPainter oldDelegate) => true;
}

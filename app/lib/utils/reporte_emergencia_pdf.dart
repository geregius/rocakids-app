import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/registro.dart';
import '../services/auth_service.dart';

/// Genera y abre (imprimir/guardar) el reporte PDF de "Modo emergencia"
/// (2026-08-19, pedido de Rafael): por cada Salida registrada HOY como
/// `modalidadRegistro == 'Emergencia'`, muestra el niño, quién lo
/// entregó según RocaKids (`nombreAcudienteEntradaOriginal`, tomado de
/// su Entrada) vs. quién lo retiró realmente en la emergencia (nombre +
/// foto + firma), y qué servidor hizo la salida — evidencia para
/// después de una evacuación u otra emergencia real.
///
/// Acotado a "hoy" (no a toda la historia) — mismo criterio de fecha que
/// el resto de la app usa para "presentes"/"registros del día"; una
/// emergencia real ocurre en un solo día.
Future<void> generarReporteEmergenciaPdf(List<Registro> registrosDeHoy) async {
  final salidasEmergencia = registrosDeHoy
      .where((r) => r.esEmergencia && r.tipoMovimiento == 'Salida')
      .toList()
    ..sort((a, b) => a.fechaMovimiento.compareTo(b.fechaMovimiento));

  // Nombres de los niños con ficha (no visitantes) — el Registro solo
  // trae el ID, no el nombre.
  final idsNinos = salidasEmergencia
      .where((r) => !r.esVisitante)
      .map((r) => r.fkIdNino)
      .toSet();
  final ninos = await AuthService().obtenerNinosPorIds(idsNinos);
  final nombresPorNinoId = {for (final n in ninos) n.documentoIdentificacion: n.nombreCompleto};

  final doc = pw.Document();
  final filas = <pw.Widget>[];
  for (final r in salidasEmergencia) {
    final nombreNino = r.esVisitante
        ? '${r.nombreNinoVisitante} (visitante)'
        : (nombresPorNinoId[r.fkIdNino] ?? '(sin datos)');
    final fotoBytes = await _descargarImagen(r.fotoEntregaEmergenciaUrl);
    final firmaBytes = await _descargarImagen(r.firmaEntregaEmergenciaUrl);
    filas.add(_bloqueSalida(r: r, nombreNino: nombreNino, fotoBytes: fotoBytes, firmaBytes: firmaBytes));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (context) => context.pageNumber == 1
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'RocaKids — Reporte de Modo Emergencia',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Generado: ${_formatearFechaHora(DateTime.now())}'),
                pw.Text('Total de salidas de emergencia hoy: ${salidasEmergencia.length}'),
                pw.Divider(),
              ],
            )
          : pw.Container(),
      build: (context) => salidasEmergencia.isEmpty
          ? [pw.Text('No hay salidas de emergencia registradas hoy.')]
          : filas,
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => doc.save(),
    name: 'reporte_emergencia_${_formatearFechaArchivo(DateTime.now())}.pdf',
  );
}

pw.Widget _bloqueSalida({
  required Registro r,
  required String nombreNino,
  required Uint8List? fotoBytes,
  required Uint8List? firmaBytes,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 16),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(nombreNino, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Hora de salida: ${_formatearFechaHora(r.fechaMovimiento)}'),
        pw.Text(
          'Entregado originalmente por (según RocaKids): '
          '${r.nombreAcudienteEntradaOriginal.isNotEmpty ? r.nombreAcudienteEntradaOriginal : "(sin dato)"}',
        ),
        pw.Text('Retirado en la emergencia por: ${r.nombreAcudienteContacto}'),
        pw.Text('Servidor que registró la salida: ${r.nombreServidor}'),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Foto de quien retiró:', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 2),
                fotoBytes != null
                    ? pw.Image(pw.MemoryImage(fotoBytes), width: 100, height: 100, fit: pw.BoxFit.cover)
                    : pw.Container(
                        width: 100,
                        height: 100,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                        child: pw.Text('Sin foto', style: const pw.TextStyle(fontSize: 8)),
                      ),
              ],
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Firma de quien retiró:', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 2),
                firmaBytes != null
                    ? pw.Image(pw.MemoryImage(firmaBytes), width: 160, height: 80, fit: pw.BoxFit.contain)
                    : pw.Container(
                        width: 160,
                        height: 80,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                        child: pw.Text('Sin firma', style: const pw.TextStyle(fontSize: 8)),
                      ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

/// `null` si la URL está vacía o si la descarga falla — un reporte con
/// una imagen faltante es mejor que un reporte que no se genera.
Future<Uint8List?> _descargarImagen(String url) async {
  if (url.isEmpty) return null;
  try {
    final respuesta = await http.get(Uri.parse(url));
    if (respuesta.statusCode == 200) return respuesta.bodyBytes;
  } catch (_) {
    // Se ignora — el bloque de este niño muestra "Sin foto/firma".
  }
  return null;
}

String _formatearFechaHora(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year} '
    '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

String _formatearFechaArchivo(DateTime f) =>
    '${f.year}${f.month.toString().padLeft(2, '0')}${f.day.toString().padLeft(2, '0')}';

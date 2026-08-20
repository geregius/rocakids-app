import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/registro.dart';
import '../services/auth_service.dart';

// Misma paleta de marca que `lib/theme/app_colors.dart` — el paquete
// `pdf` no puede reutilizar `Color` de Flutter directamente, así que se
// repite en `PdfColor` acá.
const _azulMarino = PdfColor.fromInt(0xFF003399);
const _rojo = PdfColor.fromInt(0xFFE50000);
const _grisClaro = PdfColor.fromInt(0xFFF7F8FA);
const _grisBorde = PdfColor.fromInt(0xFFDDDDDD);

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

  final logoBytes = (await rootBundle.load(
    'assets/images/logo_rocakids_compacto.png',
  )).buffer.asUint8List();
  final logo = pw.MemoryImage(logoBytes);
  final ahora = DateTime.now();

  final bloques = <pw.Widget>[];
  for (var i = 0; i < salidasEmergencia.length; i++) {
    final r = salidasEmergencia[i];
    final nombreNino = r.esVisitante
        ? '${r.nombreNinoVisitante} (visitante)'
        : (nombresPorNinoId[r.fkIdNino] ?? '(sin datos)');
    final fotoBytes = await _descargarImagen(r.fotoEntregaEmergenciaUrl);
    final firmaBytes = await _descargarImagen(r.firmaEntregaEmergenciaUrl);
    bloques.add(
      _bloqueSalida(
        numero: i + 1,
        r: r,
        nombreNino: nombreNino,
        fotoBytes: fotoBytes,
        firmaBytes: firmaBytes,
      ),
    );
  }

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
      header: (context) => context.pageNumber == 1
          ? _encabezadoCompleto(logo, salidasEmergencia.length, ahora)
          : _encabezadoCompacto(logo),
      footer: (context) => _pie(context.pageNumber, context.pagesCount, ahora),
      build: (context) => salidasEmergencia.isEmpty ? [_estadoVacio()] : bloques,
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => doc.save(),
    name: 'reporte_emergencia_${_formatearFechaArchivo(ahora)}.pdf',
  );
}

pw.Widget _encabezadoCompleto(pw.MemoryImage logo, int total, DateTime generado) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(height: 34, width: 34, child: pw.Image(logo)),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'RocaKids',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: _azulMarino,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Reporte de Modo Emergencia',
                  style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _rojo,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'EMERGENCIA',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          color: _grisClaro,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generado: ${_formatearFechaHora(generado)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Total de salidas de emergencia: $total',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 14),
    ],
  );
}

pw.Widget _encabezadoCompacto(pw.MemoryImage logo) {
  return pw.Column(
    children: [
      pw.Row(
        children: [
          pw.Container(height: 16, width: 16, child: pw.Image(logo)),
          pw.SizedBox(width: 6),
          pw.Text(
            'RocaKids — Reporte de Modo Emergencia',
            style: pw.TextStyle(
              fontSize: 9,
              color: _azulMarino,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Divider(color: _grisBorde, thickness: 0.7),
      pw.SizedBox(height: 8),
    ],
  );
}

pw.Widget _pie(int pagina, int totalPaginas, DateTime generado) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'RocaKids · ${_formatearFechaArchivoLegible(generado)}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
        pw.Text(
          'Página $pagina de $totalPaginas',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ],
    ),
  );
}

pw.Widget _estadoVacio() {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 40),
    alignment: pw.Alignment.center,
    child: pw.Text(
      'No hay salidas de emergencia registradas hoy.',
      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
    ),
  );
}

pw.Widget _bloqueSalida({
  required int numero,
  required Registro r,
  required String nombreNino,
  required Uint8List? fotoBytes,
  required Uint8List? firmaBytes,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _grisBorde, width: 0.8),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: const pw.BoxDecoration(
            color: _azulMarino,
            borderRadius: pw.BorderRadius.only(
              topLeft: pw.Radius.circular(6),
              topRight: pw.Radius.circular(6),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '$numero. $nombreNino',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                _formatearFechaHora(r.fechaMovimiento),
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
              ),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _filaDato(
                      'Entregado originalmente (según RocaKids)',
                      r.nombreAcudienteEntradaOriginal.isNotEmpty
                          ? r.nombreAcudienteEntradaOriginal
                          : '(sin dato)',
                    ),
                    _filaDato('Retirado en la emergencia por', r.nombreAcudienteContacto),
                    _filaDato('Servidor que registró la salida', r.nombreServidor),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Column(
                children: [
                  _imagenConEtiqueta('Foto', fotoBytes, 90, 90, pw.BoxFit.cover),
                  pw.SizedBox(height: 8),
                  _imagenConEtiqueta('Firma', firmaBytes, 90, 45, pw.BoxFit.contain),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _filaDato(String etiqueta, String valor) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          etiqueta.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7,
            color: PdfColors.grey600,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Text(valor, style: const pw.TextStyle(fontSize: 10)),
      ],
    ),
  );
}

pw.Widget _imagenConEtiqueta(
  String etiqueta,
  Uint8List? bytes,
  double ancho,
  double alto,
  pw.BoxFit ajuste,
) {
  return pw.Column(
    children: [
      pw.Container(
        width: ancho,
        height: alto,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _grisBorde),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: bytes != null
            ? pw.Image(pw.MemoryImage(bytes), fit: ajuste)
            : pw.Text(
                'Sin ${etiqueta.toLowerCase()}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
                textAlign: pw.TextAlign.center,
              ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
    ],
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

String _formatearFechaArchivoLegible(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

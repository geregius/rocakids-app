import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/manual_contenido.dart';

// Misma paleta que `lib/theme/app_colors.dart` — ver
// `reporte_emergencia_pdf.dart` para la misma decisión (el paquete
// `pdf` no puede reutilizar `Color` de Flutter).
const _azulMarino = PdfColor.fromInt(0xFF003399);
const _grisClaro = PdfColor.fromInt(0xFFF7F8FA);
const _grisBorde = PdfColor.fromInt(0xFFDDDDDD);
const _grisTexto = PdfColor.fromInt(0xFF444444);

/// Genera y abre (imprimir/guardar) el PDF del manual de usuario
/// (2026-08-20): un capítulo por audiencia, con la misma imagen y texto
/// que `ManualUsuarioScreen`. Carga cada captura desde
/// `assets/images/manual/` (empaquetadas con la app, no hay descarga de
/// red de por medio, a diferencia del reporte de emergencia).
Future<void> generarManualPdf() async {
  final logoBytes = (await rootBundle.load(
    'assets/images/logo_rocakids_compacto.png',
  )).buffer.asUint8List();
  final logo = pw.MemoryImage(logoBytes);

  final imagenes = <String, pw.MemoryImage>{};
  for (final capitulo in manualCapitulos) {
    for (final seccion in capitulo.secciones) {
      if (imagenes.containsKey(seccion.imagen)) continue;
      final bytes = (await rootBundle.load(
        'assets/images/manual/${seccion.imagen}',
      )).buffer.asUint8List();
      imagenes[seccion.imagen] = pw.MemoryImage(bytes);
    }
  }

  final doc = pw.Document();

  for (final capitulo in manualCapitulos) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
        header: (context) => context.pageNumber == 1
            ? _encabezadoCapitulo(logo, capitulo)
            : _encabezadoCompacto(logo, capitulo.titulo),
        footer: (context) => _pie(context.pageNumber, context.pagesCount),
        build: (context) => [
          for (final seccion in capitulo.secciones)
            _bloqueSeccion(seccion, imagenes[seccion.imagen]!),
        ],
      ),
    );
  }

  await Printing.layoutPdf(
    onLayout: (format) async => doc.save(),
    name: 'manual_rocakids.pdf',
  );
}

pw.Widget _encabezadoCapitulo(pw.MemoryImage logo, ManualCapitulo capitulo) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(height: 30, width: 30, child: pw.Image(logo)),
          pw.SizedBox(width: 10),
          pw.Text(
            'RocaKids',
            style: pw.TextStyle(
              fontSize: 10,
              color: _azulMarino,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        capitulo.titulo,
        style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        capitulo.descripcion,
        style: pw.TextStyle(fontSize: 10, color: _grisTexto),
      ),
      pw.SizedBox(height: 14),
    ],
  );
}

pw.Widget _encabezadoCompacto(pw.MemoryImage logo, String titulo) {
  return pw.Column(
    children: [
      pw.Row(
        children: [
          pw.Container(height: 14, width: 14, child: pw.Image(logo)),
          pw.SizedBox(width: 6),
          pw.Text(
            'RocaKids — $titulo',
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

pw.Widget _pie(int pagina, int totalPaginas) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Manual de usuario RocaKids',
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

pw.Widget _bloqueSeccion(ManualSeccion seccion, pw.MemoryImage imagen) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 16),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _grisBorde, width: 0.8),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.ClipRRect(
          horizontalRadius: 6,
          verticalRadius: 6,
          child: pw.Image(imagen, fit: pw.BoxFit.cover, height: 170),
        ),
        pw.Container(
          width: double.infinity,
          color: _grisClaro,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: pw.Text(
            seccion.titulo,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _azulMarino,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final punto in seccion.puntos)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        margin: const pw.EdgeInsets.only(top: 4, right: 6),
                        width: 4,
                        height: 4,
                        decoration: const pw.BoxDecoration(
                          color: _azulMarino,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          punto,
                          style: const pw.TextStyle(fontSize: 9.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

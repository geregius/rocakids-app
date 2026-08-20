import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

/// Abre la cámara para escanear el QR de una manilla y devuelve el texto
/// leído, o `null` si se canceló. Pensado para usarse tanto al registrar
/// una Entrada (llenar el número de manilla) como al dar una Salida por
/// manilla — el contenido del QR se trata como texto plano, sin importar
/// qué formato traiga de fábrica.
Future<String?> escanearCodigoManilla(BuildContext context) {
  // Sin animación de transición a propósito: en Flutter Web la vista de
  // cámara del plugin es un <video> embebido (platform view), y los
  // platform views no componen bien bajo el Transform/Opacity de una
  // transición animada — en celular (donde SÍ se usa esta vista, a
  // diferencia de escritorio) eso se veía como pantalla negra aunque la
  // cámara sí estuviera funcionando (encontrado 2026-08-19).
  return Navigator.of(context).push<String>(
    PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const _PantallaEscanerManilla(),
    ),
  );
}

class _PantallaEscanerManilla extends StatefulWidget {
  const _PantallaEscanerManilla();

  @override
  State<_PantallaEscanerManilla> createState() => _PantallaEscanerManillaState();
}

class _PantallaEscanerManillaState extends State<_PantallaEscanerManilla> {
  bool _yaLeido = false;
  bool _tardando = false;
  Key _scannerKey = UniqueKey();
  Timer? _timerTardanza;

  // En algunos navegadores/celulares el lector de códigos necesita
  // descargar una librería de un CDN externo (ver docs/estado-proyecto.md
  // sección 8) — si esa descarga se cuelga (red del celular, filtrado del
  // operador, etc.), la cámara se queda cargando PARA SIEMPRE sin ningún
  // error visible, porque el paquete no tiene un timeout propio para ese
  // caso. Esto no lo puede arreglar la app directamente (haría falta
  // parchear un archivo de un tercero, riesgoso sin poder probarlo en un
  // celular real) — pero si tarda más de lo normal, se avisa con
  // claridad y se ofrece reintentar o escribir el código a mano, en vez
  // de dejar a la persona mirando una pantalla negra sin explicación
  // (encontrado 2026-08-19).
  static const _umbralTardanza = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _iniciarTimerTardanza();
  }

  void _iniciarTimerTardanza() {
    _timerTardanza?.cancel();
    _timerTardanza = Timer(_umbralTardanza, () {
      if (mounted) setState(() => _tardando = true);
    });
  }

  void _reintentar() {
    setState(() {
      _tardando = false;
      _scannerKey = UniqueKey();
    });
    _iniciarTimerTardanza();
  }

  @override
  void dispose() {
    _timerTardanza?.cancel();
    super.dispose();
  }

  void _onDetect(BarcodeCapture captura) {
    if (_yaLeido || captura.barcodes.isEmpty) return;
    final codigo = captura.barcodes.first.rawValue;
    if (codigo == null || codigo.trim().isEmpty) return;
    _yaLeido = true;
    Navigator.of(context).pop(codigo.trim());
  }

  Future<void> _ingresarManualmente() async {
    final controller = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ingresar código manualmente'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Código de la manilla'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Usar este código'),
          ),
        ],
      ),
    );
    if (codigo != null && codigo.isNotEmpty && mounted) {
      Navigator.of(context).pop(codigo);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear manilla'),
        backgroundColor: AppColors.azulMarino,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            key: _scannerKey,
            onDetect: _onDetect,
            placeholderBuilder: (context) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se pudo abrir la cámara. Revisa que le hayas dado '
                  'permiso de cámara a este sitio, o usa "Ingresar código '
                  'manualmente" abajo.\n\n${error.errorCode.message}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          if (_tardando)
            Container(
              color: Colors.black87,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.hourglass_bottom,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'La cámara está tardando más de lo normal.\n'
                        'Puede ser tu conexión o tu navegador — intenta de '
                        'nuevo, o usa "Ingresar código manualmente" abajo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _reintentar,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton.icon(
                  onPressed: _ingresarManualmente,
                  icon: const Icon(Icons.edit, color: Colors.white),
                  label: const Text(
                    'Ingresar código manualmente',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black54,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

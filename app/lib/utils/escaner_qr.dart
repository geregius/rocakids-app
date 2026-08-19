import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

/// Abre la cámara para escanear el QR de una manilla y devuelve el texto
/// leído, o `null` si se canceló. Pensado para usarse tanto al registrar
/// una Entrada (llenar el número de manilla) como al dar una Salida por
/// manilla — el contenido del QR se trata como texto plano, sin importar
/// qué formato traiga de fábrica.
Future<String?> escanearCodigoManilla(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const _PantallaEscanerManilla()),
  );
}

class _PantallaEscanerManilla extends StatefulWidget {
  const _PantallaEscanerManilla();

  @override
  State<_PantallaEscanerManilla> createState() => _PantallaEscanerManillaState();
}

class _PantallaEscanerManillaState extends State<_PantallaEscanerManilla> {
  bool _yaLeido = false;

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
          MobileScanner(onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton.icon(
                  onPressed: _ingresarManualmente,
                  icon: const Icon(Icons.keyboard, color: Colors.white),
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

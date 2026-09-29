import 'package:flutter/material.dart';

/// Abre una foto en pantalla completa para verla más grande (2026-09-29,
/// pedido de Rafael: "poder ampliar la foto a nivel visual solamente").
///
/// Es SOLO visual: no guarda ni descarga otra versión, usa la misma URL
/// que ya se muestra en miniatura — las miniaturas de las fichas cargan
/// la imagen completa (no hay versión reducida en Storage), así que al
/// ampliarla normalmente sale de la caché del navegador sin volver a
/// descargarse. Se puede acercar con dos dedos o con la rueda del mouse.
Future<void> mostrarFotoAmpliada(BuildContext context, String url) {
  if (url.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progreso) => progreso == null
                      ? child
                      : const CircularProgressIndicator(color: Colors.white),
                  errorBuilder: (context, error, stack) => const Text(
                    'No se pudo cargar la foto.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          // "Volver" arriba a la izquierda (2026-09-29, pedido de Rafael),
          // igual que en las fichas: antes solo había una X pequeña en la
          // esquina, poco evidente sobre la foto. Fondo semitransparente
          // para que se lea sobre cualquier imagen.
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black54,
                ),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Envuelve un avatar para que al tocarlo se abra la foto ampliada. Si no
/// hay foto, devuelve el avatar tal cual (no hay nada que ampliar).
class FotoAmpliable extends StatelessWidget {
  final String url;
  final Widget child;

  const FotoAmpliable({super.key, required this.url, required this.child});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return child;
    return Tooltip(
      message: 'Ver foto',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => mostrarFotoAmpliada(context, url),
        child: child,
      ),
    );
  }
}

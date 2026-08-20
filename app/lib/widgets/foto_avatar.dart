import 'package:flutter/material.dart';

/// Avatar circular con foto de red que SÍ distingue "cargando" de
/// "falló" de "sin foto" — a diferencia de `CircleAvatar(backgroundImage:
/// NetworkImage(...))`, que en los tres casos de error/carga lenta se ve
/// igual (círculo en blanco), lo cual en una red móvil lenta se confunde
/// con "la foto no existe" (encontrado 2026-08-19, ver docs/estado-proyecto.md).
class FotoAvatar extends StatelessWidget {
  final String url;
  final double radius;
  final IconData iconoSinFoto;
  final Color? backgroundColor;
  final Color? iconColor;

  const FotoAvatar({
    super.key,
    required this.url,
    this.radius = 20,
    this.iconoSinFoto = Icons.person,
    this.backgroundColor,
    this.iconColor,
  });

  Widget _fallback() => CircleAvatar(
    radius: radius,
    backgroundColor: backgroundColor,
    child: Icon(iconoSinFoto, color: iconColor),
  );

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _fallback();
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => _fallback(),
        ),
      ),
    );
  }
}

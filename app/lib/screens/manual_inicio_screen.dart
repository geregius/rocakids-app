import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'manual_usuario_screen.dart';
import 'video_tutoriales_screen.dart';

/// Punto de entrada de "Manual de usuario" (2026-08-22, pedido de
/// Rafael): antes el ítem del menú abría directo el manual en PDF; ahora
/// primero se elige el formato. "Manual en PDF" abre exactamente lo que
/// ya existía (`ManualUsuarioScreen`, sin cambios); "Video Tutoriales"
/// es la sección nueva, con sus propios videos filtrados por audiencia.
class ManualInicioScreen extends StatelessWidget {
  final UsuarioApp usuario;

  const ManualInicioScreen({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: usuario,
      seccionActiva: 'Manual de usuario',
      construirPantalla: () => ManualInicioScreen(usuario: usuario),
      body: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Manual de usuario',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  '¿Cómo prefieres aprender a usar RocaKids?',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _TarjetaFormato(
                      icono: Icons.picture_as_pdf,
                      color: AppColors.azulMarino,
                      titulo: 'Manual en PDF',
                      subtitulo: 'Guía ilustrada, con capturas de la app',
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => ManualUsuarioScreen(usuario: usuario),
                        ),
                      ),
                    ),
                    _TarjetaFormato(
                      icono: Icons.play_circle_fill,
                      color: AppColors.amarillo,
                      colorTexto: AppColors.textoPrincipal,
                      titulo: 'Video Tutoriales',
                      subtitulo: 'Aprende viendo videos cortos',
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => VideoTutorialesScreen(usuario: usuario),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaFormato extends StatelessWidget {
  final IconData icono;
  final Color color;
  final Color colorTexto;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _TarjetaFormato({
    required this.icono,
    required this.color,
    this.colorTexto = Colors.white,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 160,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icono, color: colorTexto, size: 36),
                const SizedBox(height: 12),
                Text(
                  titulo,
                  style: TextStyle(
                    color: colorTexto,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitulo,
                  style: TextStyle(color: colorTexto.withValues(alpha: 0.85), fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Hoja "Información de la App" (2026-08-20, pedido de Rafael): datos de
/// autoría y derechos de uso — mismo lugar del menú para todos (servidor
/// o acudiente), entre "Cambiar contraseña" y "Cerrar sesión". No
/// depende de ningún dato de Firestore, es contenido fijo.
class InformacionAppSheet extends StatelessWidget {
  const InformacionAppSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.asset(
                'assets/images/logo_rocakids_compacto.png',
                height: 64,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Información de la App',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Versión 1.0.0',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _seccion(
              context,
              titulo: 'Desarrollo',
              texto:
                  'Esta aplicación fue desarrollada por Rafael Balaguera '
                  'Bonitto, en exclusividad para el ministerio infantil '
                  'RocaKids de la Iglesia Casa Sobre la Roca Armenia.',
            ),
            const SizedBox(height: 16),
            _seccion(
              context,
              titulo: 'Derechos de uso',
              texto:
                  'Todos los derechos de uso, administración y contenido '
                  'de esta aplicación pertenecen a la Iglesia Casa Sobre '
                  'la Roca Armenia. Su uso está reservado exclusivamente '
                  'al ministerio infantil RocaKids.',
            ),
            const SizedBox(height: 16),
            _seccion(
              context,
              titulo: 'Privacidad de la información',
              texto:
                  'Los datos registrados (niños, acudientes y servidores) '
                  'se usan únicamente para la administración, seguridad y '
                  'control de asistencia del ministerio infantil RocaKids.',
            ),
            const SizedBox(height: 24),
            Text(
              '© $anioActual Iglesia Casa Sobre la Roca Armenia.\n'
              'Todos los derechos reservados.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textoPrincipal.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccion(BuildContext context, {required String titulo, required String texto}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.azulMarino,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(texto, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

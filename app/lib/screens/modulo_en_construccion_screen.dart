import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'ninos_presentes_screen.dart';

/// "Inicio" para roles de servidor *distintos* a administrador. Antes
/// era solo un mensaje de "módulo en construcción" — la mayoría de sus
/// herramientas reales YA existen (Registro de asistencia, Menores
/// Registrados, etc.), solo no se veían desde acá. Rediseñado 2026-08-21
/// (pedido de Rafael, "algo atractivo, que no genere dificultad ni haga
/// más lenta la app") con saludo según la hora del día y accesos
/// directos a las 2 pantallas que usa CUALQUIER rol de servidor — a
/// propósito SIN ninguna consulta nueva a Firestore (ni "presentes
/// ahora" ni "cumpleaños de hoy"): esos datos ya se calculan en las
/// pantallas de destino, duplicarlos aquí sumaría lecturas y latencia
/// sin necesidad.
class ModuloEnConstruccionScreen extends StatelessWidget {
  final UsuarioApp usuario;

  const ModuloEnConstruccionScreen({super.key, required this.usuario});

  String _saludo() {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: usuario,
      seccionActiva: 'Inicio',
      construirPantalla: () => ModuloEnConstruccionScreen(usuario: usuario),
      body: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_saludo()}, ${usuario.nombre}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                usuario.rol.etiqueta,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.azulClaro),
              ),
              const SizedBox(height: 28),
              Text('Accesos rápidos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              // "Registro de asistencia" ya no es un acceso aparte
              // (2026-08-24) — se une dentro de "Menores Registrados",
              // que ahora tiene su propio botón "+" para eso mismo.
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _TarjetaAcceso(
                    icono: Icons.fact_check,
                    color: AppColors.amarillo,
                    colorTexto: AppColors.textoPrincipal,
                    titulo: 'Menores Registrados',
                    subtitulo: 'Quiénes están en el salón, o registra uno nuevo',
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => NinosPresentesScreen(usuario: usuario),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaAcceso extends StatelessWidget {
  final IconData icono;
  final Color color;
  final Color colorTexto;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _TarjetaAcceso({
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
      width: 260,
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
              children: [
                Icon(icono, color: colorTexto, size: 32),
                const SizedBox(height: 12),
                Text(
                  titulo,
                  style: TextStyle(
                    color: colorTexto,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
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

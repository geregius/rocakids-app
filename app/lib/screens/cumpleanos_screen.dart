import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'nino_detalle_sheet.dart';

/// Sección "Cumpleaños" (2026-08-18, pedido de Rafael) — para todos los
/// roles principales (`usuario.rol.esRolDeServidor`, mismo conjunto que
/// "Registro de asistencia"): niños que cumplen años hoy o cumplieron en
/// los últimos 7 días (`AuthService.obtenerNinosQueCumplieronEstaSemana`),
/// para poder felicitarlos. Ordenados del cumpleaños más reciente al más
/// antiguo (hoy primero). Tocar un niño abre su ficha completa.
class CumpleanosScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const CumpleanosScreen({super.key, required this.usuario});

  @override
  State<CumpleanosScreen> createState() => _CumpleanosScreenState();
}

class _CumpleanosScreenState extends State<CumpleanosScreen> {
  final _authService = AuthService();
  late Future<List<Nino>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _authService.obtenerNinosQueCumplieronEstaSemana();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Cumpleaños',
      body: FutureBuilder<List<Nino>>(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final ninos = [...?snapshot.data]..sort((a, b) {
            final diasA = diasDesdeCumpleanos(a.fechaNacimiento) ?? 99;
            final diasB = diasDesdeCumpleanos(b.fechaNacimiento) ?? 99;
            final porDia = diasA.compareTo(diasB);
            return porDia != 0
                ? porDia
                : a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase());
          });

          if (ninos.isEmpty) {
            return const Center(
              child: Text('Ningún niño ha cumplido años en la última semana.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ninos.length,
            itemBuilder: (context, i) => _CumpleanosTile(
              nino: ninos[i],
              usuario: widget.usuario,
            ),
          );
        },
      ),
    );
  }
}

class _CumpleanosTile extends StatelessWidget {
  final Nino nino;
  final UsuarioApp usuario;

  const _CumpleanosTile({required this.nino, required this.usuario});

  String _etiquetaFecha() {
    final dias = diasDesdeCumpleanos(nino.fechaNacimiento);
    if (dias == null) return '';
    if (dias == 0) return 'Cumple hoy';
    if (dias == 1) return 'Cumplió ayer';
    return 'Cumplió hace $dias días';
  }

  @override
  Widget build(BuildContext context) {
    final edad = calcularEdad(nino.fechaNacimiento);
    final grupo = grupoParaEdad(edad);
    final hoy = diasDesdeCumpleanos(nino.fechaNacimiento) == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => NinoDetalleSheet(nino: nino, usuario: usuario),
        ),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.amarillo,
          backgroundImage: nino.fotoUrl.isNotEmpty ? NetworkImage(nino.fotoUrl) : null,
          child: nino.fotoUrl.isEmpty
              ? const Icon(Icons.child_care, color: AppColors.textoPrincipal)
              : null,
        ),
        title: Text(nino.nombreCompleto),
        subtitle: Text(
          grupo != null ? 'Cumple $edad años · Grupo $grupo' : 'Cumple $edad años',
        ),
        trailing: Chip(
          avatar: Icon(
            Icons.cake,
            size: 18,
            color: hoy ? Colors.white : AppColors.azulMarino,
          ),
          label: Text(_etiquetaFecha()),
          labelStyle: TextStyle(color: hoy ? Colors.white : AppColors.azulMarino),
          backgroundColor: hoy ? AppColors.rojo : AppColors.amarillo.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/registro.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'nino_detalle_sheet.dart';

// Igual criterio que `ninos_presentes_screen.dart`: en la práctica
// SIEMPRE significa "mayor de 11 años" (`grupoParaEdad()` devuelve null
// a partir de esa edad) — nunca "menor de 2", el selector de fecha de
// nacimiento no deja registrar a nadie por debajo del mínimo.
const _mayoresDeOnce = 'Mayores de 11 años';

/// Sección "Cumpleaños niños" (2026-08-18, renombrada 2026-08-19 al
/// agregar la versión de servidores) — para todos los roles principales
/// (`usuario.rol.esRolDeServidor`, mismo conjunto que "Registro de
/// asistencia"): de los niños que cumplen años hoy o cumplieron en los
/// últimos 7 días (`AuthService.obtenerNinosQueCumplieronEstaSemana`),
/// muestra solo los que están PRESENTES HOY — para que el servidor sepa
/// a quién felicitar mientras está ahí, no una lista genérica de
/// cumpleaños de niños que ni siquiera vinieron.
///
/// **2026-08-24 (pedido de Rafael, dos vueltas el mismo día):**
/// - No se tocó `AuthService.obtenerNinosQueCumplieronEstaSemana` (sigue
///   igual) ni, mucho menos, la Cloud Function `correoCumpleanosDiario`
///   (`app/functions/index.js`), que tiene su propia consulta en
///   Node.js completamente aparte — el correo automático sigue exacto.
/// - **Primera vuelta:** se filtró a niños con `totalEntradas > 0` (ya
///   asistieron alguna vez) y se agruparon por grupo de edad.
/// - **Segunda vuelta, reemplaza el filtro anterior:** Rafael aclaró
///   que el objetivo real es mostrar a quién felicitar EN EL MOMENTO,
///   así que el filtro pasó de "alguna vez asistió" a "está presente
///   HOY" — mismo criterio de presencia que "Menores Registrados"
///   (`calcularPresentes()`, `models/registro.dart`), vía
///   `AuthService.registrosDeHoy()`. Como consecuencia, `totalEntradas`
///   ya no hace falta revisarlo aparte: estar presente hoy ya implica
///   tener al menos una Entrada.
class CumpleanosNinosScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const CumpleanosNinosScreen({super.key, required this.usuario});

  @override
  State<CumpleanosNinosScreen> createState() => _CumpleanosNinosScreenState();
}

class _CumpleanosNinosScreenState extends State<CumpleanosNinosScreen> {
  final _authService = AuthService();
  late Future<List<Nino>> _futuroCumpleaneros;

  @override
  void initState() {
    super.initState();
    _futuroCumpleaneros = _authService.obtenerNinosQueCumplieronEstaSemana();
  }

  int _comparar(Nino a, Nino b) {
    final diasA = diasDesdeCumpleanos(a.fechaNacimiento) ?? 99;
    final diasB = diasDesdeCumpleanos(b.fechaNacimiento) ?? 99;
    final porDia = diasA.compareTo(diasB);
    return porDia != 0
        ? porDia
        : a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase());
  }

  Map<String, List<Nino>> _agruparPorEdad(List<Nino> ninos) {
    final grupos = <String, List<Nino>>{};
    for (final n in ninos) {
      final grupo = grupoParaEdad(calcularEdad(n.fechaNacimiento)) ?? _mayoresDeOnce;
      grupos.putIfAbsent(grupo, () => []).add(n);
    }
    for (final lista in grupos.values) {
      lista.sort(_comparar);
    }
    return grupos;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Cumpleaños niños',
      body: FutureBuilder<List<Nino>>(
        future: _futuroCumpleaneros,
        builder: (context, snapshotCumpleaneros) {
          if (snapshotCumpleaneros.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshotCumpleaneros.hasError) {
            return Center(child: Text('Error: ${snapshotCumpleaneros.error}'));
          }
          final cumpleaneros = snapshotCumpleaneros.data ?? [];
          if (cumpleaneros.isEmpty) {
            return const Center(
              child: Text('Ningún niño ha cumplido años en la última semana.'),
            );
          }

          // Reactivo (StreamBuilder, no Future) porque "quién está
          // presente" cambia en vivo durante el día — si un niño de
          // cumpleaños entra o sale, la lista se actualiza sola.
          return StreamBuilder<List<Registro>>(
            stream: _authService.registrosDeHoy(),
            builder: (context, snapshotRegistros) {
              if (snapshotRegistros.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshotRegistros.hasError) {
                return Center(child: Text('Error: ${snapshotRegistros.error}'));
              }
              final presentes = calcularPresentes(snapshotRegistros.data ?? []);
              final presentesPorNino = {
                for (final r in presentes)
                  if (!r.esVisitante) r.fkIdNino: r,
              };
              final ninos = cumpleaneros
                  .where((n) => presentesPorNino.containsKey(n.documentoIdentificacion))
                  .toList();

              if (ninos.isEmpty) {
                return const Center(
                  child: Text('Ningún niño presente hoy está de cumpleaños.'),
                );
              }

              final grupos = _agruparPorEdad(ninos);
              final ordenados = [
                ...gruposEdad,
                if (grupos.containsKey(_mayoresDeOnce)) _mayoresDeOnce,
              ];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final grupo in ordenados)
                    if (grupos[grupo] != null)
                      _GrupoCumpleanosSection(
                        nombre: grupo,
                        ninos: grupos[grupo]!,
                        usuario: widget.usuario,
                        presentesPorNino: presentesPorNino,
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _GrupoCumpleanosSection extends StatelessWidget {
  final String nombre;
  final List<Nino> ninos;
  final UsuarioApp usuario;
  final Map<String, Registro> presentesPorNino;

  const _GrupoCumpleanosSection({
    required this.nombre,
    required this.ninos,
    required this.usuario,
    required this.presentesPorNino,
  });

  @override
  Widget build(BuildContext context) {
    final rangoEdad = rangoEdadPorGrupo[nombre];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              rangoEdad != null
                  ? 'Grupo $nombre · $rangoEdad (${ninos.length})'
                  // "Mayores de 11 años" ya se lee bien solo, sin el
                  // prefijo "Grupo" delante.
                  : nombre == _mayoresDeOnce
                  ? '$nombre (${ninos.length})'
                  : 'Grupo $nombre (${ninos.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.azulMarino,
                fontWeight: FontWeight.bold,
              ),
            ),
            children: [
              const Divider(height: 1),
              for (final n in ninos)
                _CumpleanosNinoTile(
                  nino: n,
                  usuario: usuario,
                  acudienteQueLoTrajoHoyId: presentesPorNino[n.documentoIdentificacion]
                      ?.fkIdAcudienteContacto,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CumpleanosNinoTile extends StatelessWidget {
  final Nino nino;
  final UsuarioApp usuario;
  final String? acudienteQueLoTrajoHoyId;

  const _CumpleanosNinoTile({
    required this.nino,
    required this.usuario,
    required this.acudienteQueLoTrajoHoyId,
  });

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
    final hoy = diasDesdeCumpleanos(nino.fechaNacimiento) == 0;

    return ListTile(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => NinoDetalleSheet(
          nino: nino,
          usuario: usuario,
          acudienteQueLoTrajoHoyId: acudienteQueLoTrajoHoyId,
        ),
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
      subtitle: Text('Cumple $edad años'),
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
    );
  }
}

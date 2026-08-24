import 'package:flutter/material.dart';

import '../models/nino.dart';
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
/// asistencia"): niños que cumplen años hoy o cumplieron en los últimos
/// 7 días (`AuthService.obtenerNinosQueCumplieronEstaSemana`), para
/// poder felicitarlos.
///
/// **2026-08-24 (pedido de Rafael):** dos cambios, SOLO en esta
/// pantalla — no se tocó `AuthService.obtenerNinosQueCumplieronEstaSemana`
/// (que ya filtraba `estadoRegistro == 'Activo'`, sigue igual) ni,
/// mucho menos, la Cloud Function `correoCumpleanosDiario`
/// (`app/functions/index.js`), que tiene su propia consulta en Node.js
/// completamente aparte y ni siquiera pasa por este código Dart — el
/// correo automático de cumpleaños sigue exactamente igual:
/// 1. Se filtra a solo niños "registrados" en el sentido de que ya
///    asistieron alguna vez (`Nino.totalEntradas > 0`) — un niño dado de
///    alta pero que nunca vino no aparece acá.
/// 2. Se agrupan por grupo de edad (José/David/Judá/Daniel/Santiago),
///    igual que "Menores Registrados", con los "mayores de 11" en su
///    propio grupo al final.
class CumpleanosNinosScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const CumpleanosNinosScreen({super.key, required this.usuario});

  @override
  State<CumpleanosNinosScreen> createState() => _CumpleanosNinosScreenState();
}

class _CumpleanosNinosScreenState extends State<CumpleanosNinosScreen> {
  final _authService = AuthService();
  late Future<List<Nino>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _authService.obtenerNinosQueCumplieronEstaSemana();
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
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          // Solo niños que ya asistieron al menos una vez — pedido de
          // Rafael, para no felicitar/mostrar a alguien que se dio de
          // alta pero nunca vino.
          final ninos = [...?snapshot.data].where((n) => n.totalEntradas > 0).toList();

          if (ninos.isEmpty) {
            return const Center(
              child: Text('Ningún niño registrado ha cumplido años en la última semana.'),
            );
          }

          final grupos = _agruparPorEdad(ninos);
          final ordenados = [...gruposEdad, if (grupos.containsKey(_mayoresDeOnce)) _mayoresDeOnce];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final grupo in ordenados)
                if (grupos[grupo] != null)
                  _GrupoCumpleanosSection(nombre: grupo, ninos: grupos[grupo]!, usuario: widget.usuario),
            ],
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

  const _GrupoCumpleanosSection({
    required this.nombre,
    required this.ninos,
    required this.usuario,
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
              for (final n in ninos) _CumpleanosNinoTile(nino: n, usuario: usuario),
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

  const _CumpleanosNinoTile({required this.nino, required this.usuario});

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

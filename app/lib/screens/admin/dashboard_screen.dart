import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/nino.dart';
import '../../models/registro.dart';
import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';

/// Nombres cortos de cada servicio para que quepan como etiqueta de eje
/// en las gráficas (los nombres completos de [serviciosDisponibles] son
/// demasiado largos). Debe cubrir todos los valores de esa lista.
const _servicioCorto = {
  'Domingo 1° Servicio': 'Dom 1°',
  'Domingo 2° Servicio': 'Dom 2°',
  'Miércoles': 'Miér',
  'Ayuno': 'Ayuno',
  'Casa2': 'Casa2',
};

/// "Dashboard" para los roles de liderazgo (administrador, columna y
/// líder de ministerio — ver [RolUsuario.puedeVerDashboard]): un
/// vistazo de cuántos niños hay HOY (reutilizando la misma lógica de
/// "presentes ahora" que `ninos_presentes_screen.dart`) y una vista
/// histórica de tendencias (asistencia por semana, comparación entre
/// servicios).
///
/// El histórico consulta `registros` directamente cada vez que se abre
/// (ver [AuthService.obtenerEntradasDesde]) — funciona bien con el
/// volumen de datos de hoy; si en el futuro se vuelve lento, se resuelve
/// con una tabla de resúmenes pre-calculados, no antes (decisión
/// 2026-08-17, ver memoria del proyecto).
///
/// El "crecimiento de niños registrados" que se había pensado para este
/// bloque queda fuera por ahora: los documentos de `ninos` no guardan
/// fecha de creación, así que no hay forma de reconstruir esa tendencia
/// para los registros que ya existen. En su lugar se muestra el total
/// actual como un dato simple, no una tendencia.
class DashboardScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const DashboardScreen({super.key, required this.usuario});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _authService = AuthService();
  bool _cargandoNinos = true;
  Map<String, Nino> _ninosPorId = {};

  @override
  void initState() {
    super.initState();
    _cargarNinos();
  }

  Future<void> _cargarNinos() async {
    try {
      final ninos = await _authService.obtenerTodosLosNinos();
      if (mounted) {
        setState(() {
          _ninosPorId = {for (final n in ninos) n.documentoIdentificacion: n};
          _cargandoNinos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoNinos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Dashboard',
      body: _cargandoNinos
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TituloBloque('Hoy'),
                const SizedBox(height: 8),
                _BloqueHoy(authService: _authService, ninosPorId: _ninosPorId),
                const SizedBox(height: 32),
                _TituloBloque('Histórico'),
                const SizedBox(height: 8),
                _BloqueHistorico(authService: _authService),
              ],
            ),
    );
  }
}

class _TituloBloque extends StatelessWidget {
  final String texto;
  const _TituloBloque(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppColors.azulMarino,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _BloqueHoy extends StatelessWidget {
  final AuthService authService;
  final Map<String, Nino> ninosPorId;

  const _BloqueHoy({required this.authService, required this.ninosPorId});

  /// Igual criterio que `ninos_presentes_screen.dart`: el último
  /// movimiento de HOY de un niño registrado decide si sigue presente;
  /// cada Entrada de un visitante cuenta por separado porque esta fase
  /// no registra su salida.
  List<Registro> _presentesAhora(List<Registro> registrosDeHoy) {
    final ultimoPorNino = <String, Registro>{};
    final visitantesPresentes = <Registro>[];
    for (final r in registrosDeHoy) {
      if (r.esVisitante) {
        if (r.tipoMovimiento == 'Entrada') visitantesPresentes.add(r);
        continue;
      }
      ultimoPorNino[r.fkIdNino] = r;
    }
    return [
      ...ultimoPorNino.values.where((r) => r.tipoMovimiento == 'Entrada'),
      ...visitantesPresentes,
    ];
  }

  bool _sinDocumento(Registro r) => r.esVisitante
      ? r.documentoNinoVisitante.isEmpty
      : (ninosPorId[r.fkIdNino]?.identificacionMenor.isEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Registro>>(
      stream: authService.registrosDeHoy(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        final registrosDeHoy = snapshot.data ?? [];
        final entradasHoy = registrosDeHoy
            .where((r) => r.tipoMovimiento == 'Entrada')
            .toList();
        final presentes = _presentesAhora(registrosDeHoy);
        final yaSalieron = entradasHoy.length - presentes.length;
        final visitantes = entradasHoy.where((r) => r.esVisitante).length;
        final sinDocumento = entradasHoy.where(_sinDocumento).length;

        final porGrupo = <String, int>{
          for (final g in gruposEdad) g: 0,
        };
        final porServicio = <String, int>{
          for (final s in serviciosDisponibles) s: 0,
        };
        for (final r in entradasHoy) {
          final grupo = gruposEdad.contains(r.grupoEdad) ? r.grupoEdad : null;
          if (grupo != null) porGrupo[grupo] = (porGrupo[grupo] ?? 0) + 1;
          if (porServicio.containsKey(r.servicio)) {
            porServicio[r.servicio] = (porServicio[r.servicio] ?? 0) + 1;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatTile(
                  etiqueta: 'Recibidos hoy',
                  valor: '${entradasHoy.length}',
                  icono: Icons.groups,
                ),
                _StatTile(
                  etiqueta: 'Presentes ahora',
                  valor: '${presentes.length}',
                  icono: Icons.child_care,
                ),
                _StatTile(
                  etiqueta: 'Ya salieron',
                  valor: '${yaSalieron < 0 ? 0 : yaSalieron}',
                  icono: Icons.logout,
                ),
                _StatTile(
                  etiqueta: 'Visitantes',
                  valor: '$visitantes',
                  icono: Icons.person_add_alt,
                ),
                _StatTile(
                  etiqueta: 'Sin documento',
                  valor: '$sinDocumento',
                  icono: Icons.badge_outlined,
                  destacar: sinDocumento > 0,
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (entradasHoy.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Todavía no hay registros hoy.')),
              )
            else ...[
              _GraficaBarras(
                titulo: 'Por grupo de edad',
                datos: porGrupo,
              ),
              const SizedBox(height: 20),
              _GraficaBarras(
                titulo: 'Por servicio',
                datos: porServicio,
                etiquetaCorta: (k) => _servicioCorto[k] ?? k,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BloqueHistorico extends StatefulWidget {
  final AuthService authService;
  const _BloqueHistorico({required this.authService});

  @override
  State<_BloqueHistorico> createState() => _BloqueHistoricoState();
}

class _BloqueHistoricoState extends State<_BloqueHistorico> {
  int _semanas = 8;
  late Future<List<Registro>> _futuroEntradas;
  Future<int>? _futuroTotalNinos;

  @override
  void initState() {
    super.initState();
    _cargar();
    _futuroTotalNinos = widget.authService.contarNinosRegistrados();
  }

  void _cargar() {
    final desde = DateTime.now().subtract(Duration(days: _semanas * 7));
    _futuroEntradas = widget.authService.obtenerEntradasDesde(
      DateTime(desde.year, desde.month, desde.day),
    );
  }

  /// Lunes de la semana que contiene [d], para agrupar por semana.
  DateTime _inicioSemana(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [4, 8, 12].map((n) {
            return ChoiceChip(
              label: Text('$n semanas'),
              selected: _semanas == n,
              onSelected: (_) => setState(() {
                _semanas = n;
                _cargar();
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Registro>>(
          future: _futuroEntradas,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            final entradas = snapshot.data ?? [];
            if (entradas.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No hay registros en este período.'),
                ),
              );
            }

            final porSemana = <DateTime, int>{};
            final hoy = DateTime.now();
            for (var i = _semanas - 1; i >= 0; i--) {
              final semana = _inicioSemana(hoy.subtract(Duration(days: i * 7)));
              porSemana[semana] = 0;
            }
            for (final r in entradas) {
              final semana = _inicioSemana(r.fechaMovimiento);
              if (porSemana.containsKey(semana)) {
                porSemana[semana] = (porSemana[semana] ?? 0) + 1;
              }
            }

            final porServicio = <String, int>{
              for (final s in serviciosDisponibles) s: 0,
            };
            for (final r in entradas) {
              if (porServicio.containsKey(r.servicio)) {
                porServicio[r.servicio] = (porServicio[r.servicio] ?? 0) + 1;
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GraficaBarras(
                  titulo: 'Entradas por semana',
                  datos: {
                    for (final e in porSemana.entries)
                      '${e.key.day}/${e.key.month}': e.value,
                  },
                ),
                const SizedBox(height: 20),
                _GraficaBarras(
                  titulo: 'Comparación entre servicios',
                  datos: porServicio,
                  etiquetaCorta: (k) => _servicioCorto[k] ?? k,
                ),
                const SizedBox(height: 20),
                FutureBuilder<int>(
                  future: _futuroTotalNinos,
                  builder: (context, snap) => _StatTile(
                    etiqueta: 'Niños registrados en el sistema',
                    valor: snap.hasData ? '${snap.data}' : '…',
                    icono: Icons.diversity_3,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final IconData icono;
  final bool destacar;

  const _StatTile({
    required this.etiqueta,
    required this.valor,
    required this.icono,
    this.destacar = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: destacar
            ? AppColors.rojo.withValues(alpha: 0.08)
            : AppColors.superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: destacar
              ? AppColors.rojo.withValues(alpha: 0.3)
              : AppColors.azulMarino.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icono,
            color: destacar ? AppColors.rojo : AppColors.azulMarino,
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: destacar ? AppColors.rojo : AppColors.textoPrincipal,
            ),
          ),
          Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Gráfica de barras genérica: una barra por cada llave de [datos], en el
/// mismo orden en que se insertaron. Un solo color de marca — no hace
/// falta codificar identidad por color porque cada barra ya lleva su
/// propia etiqueta en el eje X.
class _GraficaBarras extends StatelessWidget {
  final String titulo;
  final Map<String, int> datos;
  final String Function(String llave)? etiquetaCorta;

  const _GraficaBarras({
    required this.titulo,
    required this.datos,
    this.etiquetaCorta,
  });

  @override
  Widget build(BuildContext context) {
    final llaves = datos.keys.toList();
    final maxValor = datos.values.isEmpty
        ? 0
        : datos.values.reduce((a, b) => a > b ? a : b);
    final techo = maxValor == 0 ? 1.0 : (maxValor * 1.2);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.azulMarino.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.azulMarino,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: techo,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: techo / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.textoPrincipal.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: techo / 4 == 0 ? 1 : techo / 4,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= llaves.length) {
                          return const SizedBox.shrink();
                        }
                        final llave = llaves[i];
                        final texto = etiquetaCorta?.call(llave) ?? llave;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            texto,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.azulOscuro,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                      '${rod.toY.toInt()}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < llaves.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: (datos[llaves[i]] ?? 0).toDouble(),
                          color: AppColors.azulMarino,
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

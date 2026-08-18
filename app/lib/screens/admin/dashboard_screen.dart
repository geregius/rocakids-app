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

const _mesesAbrev = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String _etiquetaMes(DateTime mes) =>
    "${_mesesAbrev[mes.month - 1]} ${mes.year.toString().substring(2)}";

DateTime _inicioMes(DateTime d) => DateTime(d.year, d.month, 1);

/// Suma (o resta, con [n] negativo) [n] meses a [d], manejando el
/// desborde de año (ej. enero - 2 meses = noviembre del año anterior).
DateTime _sumarMeses(DateTime d, int n) {
  final total = d.year * 12 + (d.month - 1) + n;
  return DateTime(total ~/ 12, total % 12 + 1, 1);
}

/// "Dashboard" para los roles de liderazgo (administrador, columna y
/// líder de ministerio — ver [RolUsuario.puedeVerDashboard]): totales
/// del sistema, un vistazo de cuántos niños hay HOY (reutilizando la
/// misma lógica de "presentes ahora" que `ninos_presentes_screen.dart`)
/// y una vista histórica de tendencias con filtros de 1/3/6/9/12 meses.
///
/// El histórico trae TODAS las Entradas alguna vez registradas en una
/// sola consulta (ver [_BloqueHistoricoState._futuroTodasLasEntradas])
/// y agrega todo del lado del cliente — así cambiar de filtro (1 a 12
/// meses) no dispara una consulta nueva, y calcular el crecimiento
/// acumulado de niños necesita conocer la primera asistencia de cada
/// uno aunque haya sido antes de la ventana seleccionada. Funciona bien
/// con el volumen de datos de hoy; si en el futuro (ej. tras importar
/// los ~3873 registros históricos del Módulo 2) se vuelve lento, se
/// resuelve con una tabla de resúmenes pre-calculados, no antes
/// (decisión 2026-08-17, ver memoria del proyecto).
///
/// El "crecimiento de niños registrados" se mide por la fecha de su
/// PRIMERA asistencia (mínimo `fechaMovimiento` de sus Entradas), no por
/// una fecha de creación del documento `ninos` — ese documento no
/// guarda cuándo se creó, así que no hay forma de reconstruir esa
/// tendencia para los niños que ya existen en el sistema.
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
    final esAdmin = widget.usuario.rol == RolUsuario.administrador;
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Dashboard',
      body: _cargandoNinos
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TituloBloque('Totales del sistema'),
                const SizedBox(height: 8),
                _BloqueTotales(authService: _authService, esAdmin: esAdmin),
                const SizedBox(height: 32),
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

/// Conteos simples de "ahora mismo" — no dependen del filtro de fecha
/// del bloque Histórico. "Servidores activos" solo se pide (y se
/// muestra) si [esAdmin]: ver docstring de
/// [AuthService.contarServidoresActivos].
class _BloqueTotales extends StatelessWidget {
  final AuthService authService;
  final bool esAdmin;

  const _BloqueTotales({required this.authService, required this.esAdmin});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: Future.wait([
        authService.contarNinosRegistrados(),
        authService.contarAcudientesRegistrados(),
        if (esAdmin) authService.contarServidoresActivos(),
      ]),
      builder: (context, snapshot) {
        final valores = snapshot.data;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatTile(
              etiqueta: 'Niños registrados',
              valor: valores != null ? '${valores[0]}' : '…',
              icono: Icons.child_care,
            ),
            _StatTile(
              etiqueta: 'Acudientes registrados',
              valor: valores != null ? '${valores[1]}' : '…',
              icono: Icons.family_restroom,
            ),
            if (esAdmin)
              _StatTile(
                etiqueta: 'Servidores activos',
                valor: valores != null ? '${valores[2]}' : '…',
                icono: Icons.volunteer_activism,
              ),
          ],
        );
      },
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

const _opcionesMeses = [1, 3, 6, 9, 12];

class _BloqueHistorico extends StatefulWidget {
  final AuthService authService;
  const _BloqueHistorico({required this.authService});

  @override
  State<_BloqueHistorico> createState() => _BloqueHistoricoState();
}

class _BloqueHistoricoState extends State<_BloqueHistorico> {
  int _meses = 3;
  late final Future<List<Registro>> _futuroTodasLasEntradas;

  @override
  void initState() {
    super.initState();
    // Todas las Entradas desde siempre, en una sola consulta — ver
    // docstring de [DashboardScreen] sobre por qué hace falta el
    // historial completo (no solo la ventana seleccionada) para el
    // crecimiento acumulado, y por qué cambiar el filtro no vuelve a
    // consultar Firestore.
    _futuroTodasLasEntradas = widget.authService.obtenerEntradasDesde(
      DateTime(2000),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: _opcionesMeses.map((n) {
            return ChoiceChip(
              label: Text(n == 1 ? '1 mes' : '$n meses'),
              selected: _meses == n,
              onSelected: (_) => setState(() => _meses = n),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Registro>>(
          future: _futuroTodasLasEntradas,
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
            final todasLasEntradas = snapshot.data ?? [];
            if (todasLasEntradas.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Todavía no hay registros.')),
              );
            }

            final hoy = DateTime.now();
            final mesesEnRango = [
              for (var i = _meses - 1; i >= 0; i--)
                _sumarMeses(_inicioMes(hoy), -i),
            ];
            final inicioVentana = mesesEnRango.first;
            final entradasEnVentana = todasLasEntradas
                .where((r) => !r.fechaMovimiento.isBefore(inicioVentana))
                .toList();

            // Asistencia por mes (todas las Entradas, visitantes
            // incluidos — mide volumen de asistencia, no niños únicos).
            final asistenciaPorMes = <String, int>{
              for (final m in mesesEnRango) _etiquetaMes(m): 0,
            };
            for (final r in entradasEnVentana) {
              final llave = _etiquetaMes(_inicioMes(r.fechaMovimiento));
              if (asistenciaPorMes.containsKey(llave)) {
                asistenciaPorMes[llave] = (asistenciaPorMes[llave] ?? 0) + 1;
              }
            }

            // Crecimiento acumulado de niños registrados: primera
            // Entrada de cada niño (fkIdNino no vacío) en TODA la
            // historia, para que el acumulado dentro de la ventana ya
            // arranque con la base correcta de niños que empezaron a
            // asistir antes del filtro seleccionado.
            final primeraAsistenciaPorNino = <String, DateTime>{};
            for (final r in todasLasEntradas) {
              if (r.esVisitante) continue;
              final actual = primeraAsistenciaPorNino[r.fkIdNino];
              if (actual == null || r.fechaMovimiento.isBefore(actual)) {
                primeraAsistenciaPorNino[r.fkIdNino] = r.fechaMovimiento;
              }
            }
            final primerasAsistencias = primeraAsistenciaPorNino.values
                .toList()
              ..sort();
            final crecimientoAcumulado = <double>[
              for (final finDeMes in mesesEnRango.map(
                (m) => _sumarMeses(m, 1),
              ))
                primerasAsistencias
                    .where((f) => f.isBefore(finDeMes))
                    .length
                    .toDouble(),
            ];

            // Comparación entre servicios, dentro de la ventana.
            final porServicio = <String, int>{
              for (final s in serviciosDisponibles) s: 0,
            };
            for (final r in entradasEnVentana) {
              if (porServicio.containsKey(r.servicio)) {
                porServicio[r.servicio] = (porServicio[r.servicio] ?? 0) + 1;
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GraficaLinea(
                  titulo: 'Crecimiento de niños registrados (acumulado)',
                  etiquetasX: mesesEnRango.map(_etiquetaMes).toList(),
                  valores: crecimientoAcumulado,
                ),
                const SizedBox(height: 20),
                _GraficaBarras(
                  titulo: 'Asistencia por mes',
                  datos: asistenciaPorMes,
                ),
                const SizedBox(height: 20),
                _GraficaBarras(
                  titulo: 'Comparación entre servicios',
                  datos: porServicio,
                  etiquetaCorta: (k) => _servicioCorto[k] ?? k,
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

/// Contenedor común (título + tarjeta) para las dos gráficas.
Widget _tarjetaGrafica(
  BuildContext context, {
  required String titulo,
  required Widget grafica,
}) {
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
        SizedBox(height: 200, child: grafica),
      ],
    ),
  );
}

FlTitlesData _ejesConEtiquetas(
  BuildContext context,
  List<String> etiquetasX,
  double techo,
) {
  final intervaloY = techo / 4 == 0 ? 1.0 : techo / 4;
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: intervaloY,
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
          if (i < 0 || i >= etiquetasX.length) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              etiquetasX[i],
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      ),
    ),
  );
}

/// Gráfica de barras genérica: una barra por cada llave de [datos], en el
/// mismo orden en que se insertaron. Un solo color de marca — no hace
/// falta codificar identidad por color porque cada barra ya lleva su
/// propia etiqueta en el eje X. Interactiva: tocar (o pasar el mouse en
/// escritorio/web) una barra muestra su valor exacto en un tooltip.
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
    final etiquetasX = [
      for (final k in llaves) etiquetaCorta?.call(k) ?? k,
    ];

    return _tarjetaGrafica(
      context,
      titulo: titulo,
      grafica: BarChart(
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
          titlesData: _ejesConEtiquetas(context, etiquetasX, techo),
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
    );
  }
}

/// Gráfica de línea para tendencias/crecimiento en el tiempo (una sola
/// serie). Interactiva: al tocar o pasar el mouse sobre la línea
/// aparece una guía vertical y un tooltip con el valor exacto de ese
/// mes — el equivalente en fl_chart a un crosshair.
class _GraficaLinea extends StatelessWidget {
  final String titulo;
  final List<String> etiquetasX;
  final List<double> valores;

  const _GraficaLinea({
    required this.titulo,
    required this.etiquetasX,
    required this.valores,
  });

  @override
  Widget build(BuildContext context) {
    final maxValor = valores.isEmpty
        ? 0.0
        : valores.reduce((a, b) => a > b ? a : b);
    final techo = maxValor == 0 ? 1.0 : (maxValor * 1.2);

    return _tarjetaGrafica(
      context,
      titulo: titulo,
      grafica: LineChart(
        LineChartData(
          minY: 0,
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
          titlesData: _ejesConEtiquetas(context, etiquetasX, techo),
          lineTouchData: LineTouchData(
            getTouchedSpotIndicator: (barData, indexes) => indexes
                .map(
                  (_) => TouchedSpotIndicatorData(
                    FlLine(
                      color: AppColors.azulMarino.withValues(alpha: 0.3),
                      strokeWidth: 2,
                    ),
                    FlDotData(
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 5,
                        color: AppColors.azulMarino,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                  ),
                )
                .toList(),
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.azulOscuro,
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '${s.y.toInt()}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < valores.length; i++)
                  FlSpot(i.toDouble(), valores[i]),
              ],
              isCurved: false,
              color: AppColors.azulMarino,
              barWidth: 2,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.azulMarino.withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

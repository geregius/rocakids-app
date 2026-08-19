import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/acudiente.dart';
import '../../models/nino.dart';
import '../../models/registro.dart';
import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';
import '../acudiente_detalle_sheet.dart';
import '../nino_detalle_sheet.dart';

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
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
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
                _BloqueTotales(authService: _authService),
                const SizedBox(height: 20),
                _BloqueAlertaGraduacion(
                  authService: _authService,
                  usuario: widget.usuario,
                ),
                const SizedBox(height: 32),
                _TituloBloque('Pendientes'),
                const SizedBox(height: 8),
                _BloquePendientes(
                  authService: _authService,
                  usuario: widget.usuario,
                ),
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
/// del bloque Histórico. Las tres estadísticas usan el mismo permiso
/// (`puedeVerInfoLiderazgo()` en firestore.rules: administrador, columna,
/// líder de ministerio — el mismo conjunto que da acceso al Dashboard),
/// así que todo quien vea esta pantalla ve las tres.
class _BloqueTotales extends StatelessWidget {
  final AuthService authService;

  const _BloqueTotales({required this.authService});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: Future.wait([
        authService.contarNinosRegistrados(),
        authService.contarAcudientesRegistrados(),
        authService.contarServidoresActivos(),
        authService.contarNinosGraduados(),
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
            _StatTile(
              etiqueta: 'Servidores activos',
              valor: valores != null ? '${valores[2]}' : '…',
              icono: Icons.volunteer_activism,
            ),
            _StatTile(
              etiqueta: 'Niños graduados',
              valor: valores != null ? '${valores[3]}' : '…',
              icono: Icons.school,
            ),
          ],
        );
      },
    );
  }
}

/// Alerta mensual pedida por Rafael (2026-08-18): qué niños cumplen
/// [edadMaximaRegistro] + 1 años ESTE MES y por lo tanto deben
/// graduarse del ministerio infantil y pasar al siguiente nivel de la
/// iglesia. A propósito NO los gradúa solo — es una alerta para que el
/// liderazgo lo gestione (ceremonia, aviso a la familia, etc.); marcar
/// a un niño como "Graduado" se sigue haciendo editando su ficha.
/// Tarjeta tocable (2026-08-18, pedido de Rafael) — igual que el bloque
/// "Pendientes": toca para ver exactamente quiénes son.
class _BloqueAlertaGraduacion extends StatelessWidget {
  final AuthService authService;
  final UsuarioApp usuario;
  const _BloqueAlertaGraduacion({
    required this.authService,
    required this.usuario,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: authService.obtenerNinosQueGraduanEsteMes().then((l) => l.length),
      builder: (context, snapshot) {
        final total = snapshot.data;
        if (total == 0) return const SizedBox.shrink();
        return _TarjetaPendiente(
          etiqueta: total == 1
              ? 'Niño que cumple ${edadMaximaRegistro + 1} años este mes'
              : 'Niños que cumplen ${edadMaximaRegistro + 1} años este mes',
          valor: total,
          icono: Icons.school,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _ListaPendientesSheet(
              titulo: 'Cumplen ${edadMaximaRegistro + 1} años este mes',
              cargar: authService.obtenerNinosQueGraduanEsteMes,
              esNino: true,
              usuario: usuario,
            ),
          ),
        );
      },
    );
  }
}

/// Bloque "Pendientes" (2026-08-18, pedido de Rafael): un dato
/// interactivo por categoría de dato faltante — al tocar una tarjeta se
/// abre la lista exacta de quiénes son (`_ListaPendientesSheet`), y
/// tocar a alguien de esa lista abre su ficha completa para poder
/// corregirlo ahí mismo. Cada conteo es una consulta acotada
/// (`where` + `count()`), no trae toda la colección salvo que se abra
/// la lista.
class _BloquePendientes extends StatelessWidget {
  final AuthService authService;
  final UsuarioApp usuario;

  const _BloquePendientes({required this.authService, required this.usuario});

  void _abrirLista(
    BuildContext context, {
    required String titulo,
    required Future<List<dynamic>> Function() cargar,
    required bool esNino,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ListaPendientesSheet(
        titulo: titulo,
        cargar: cargar,
        esNino: esNino,
        usuario: usuario,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: Future.wait([
        authService.contarNinosSinFoto(),
        authService.contarNinosSinDocumento(),
        authService.contarAcudientesSinFoto(),
        authService.contarAcudientesConCorreoPendiente(),
      ]),
      builder: (context, snapshot) {
        final valores = snapshot.data;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _TarjetaPendiente(
              etiqueta: 'Niños sin foto',
              valor: valores != null ? valores[0] : null,
              icono: Icons.no_photography,
              onTap: () => _abrirLista(
                context,
                titulo: 'Niños sin foto',
                cargar: authService.obtenerNinosSinFoto,
                esNino: true,
              ),
            ),
            _TarjetaPendiente(
              etiqueta: 'Niños sin documento',
              valor: valores != null ? valores[1] : null,
              icono: Icons.badge_outlined,
              onTap: () => _abrirLista(
                context,
                titulo: 'Niños sin documento',
                cargar: authService.obtenerNinosSinDocumento,
                esNino: true,
              ),
            ),
            _TarjetaPendiente(
              etiqueta: 'Acudientes sin foto',
              valor: valores != null ? valores[2] : null,
              icono: Icons.no_photography,
              onTap: () => _abrirLista(
                context,
                titulo: 'Acudientes sin foto',
                cargar: authService.obtenerAcudientesSinFoto,
                esNino: false,
              ),
            ),
            _TarjetaPendiente(
              etiqueta: 'Acudientes con correo pendiente',
              valor: valores != null ? valores[3] : null,
              icono: Icons.mail_outline,
              onTap: () => _abrirLista(
                context,
                titulo: 'Acudientes con correo pendiente',
                cargar: authService.obtenerAcudientesConCorreoPendiente,
                esNino: false,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Tarjeta de estadística tocable — como [_StatTile] pero interactiva:
/// se deshabilita mientras el conteo sigue en 0 (nada que mostrar) y
/// muestra un ícono de flecha cuando sí hay algo que ver.
class _TarjetaPendiente extends StatelessWidget {
  final String etiqueta;
  final int? valor;
  final IconData icono;
  final VoidCallback onTap;

  const _TarjetaPendiente({
    required this.etiqueta,
    required this.valor,
    required this.icono,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hayAlgo = (valor ?? 0) > 0;
    return InkWell(
      onTap: hayAlgo ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hayAlgo
              ? AppColors.amarillo.withValues(alpha: 0.12)
              : AppColors.superficie,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hayAlgo
                ? AppColors.amarillo.withValues(alpha: 0.5)
                : AppColors.azulMarino.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: AppColors.azulMarino),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor != null ? '$valor' : '…',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textoPrincipal,
                    ),
                  ),
                  Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (hayAlgo)
              const Icon(Icons.chevron_right, color: AppColors.textoPrincipal),
          ],
        ),
      ),
    );
  }
}

/// Hoja inferior con la lista exacta de niños o acudientes de una
/// categoría de "Pendientes". Tocar a alguien abre su ficha completa
/// (misma que usan el resto de pantallas) para poder corregirlo ahí.
class _ListaPendientesSheet extends StatelessWidget {
  final String titulo;
  final Future<List<dynamic>> Function() cargar;
  final bool esNino;
  final UsuarioApp usuario;

  const _ListaPendientesSheet({
    required this.titulo,
    required this.cargar,
    required this.esNino,
    required this.usuario,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return FutureBuilder<List<dynamic>>(
          future: cargar(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                    '$titulo (${items.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final nombre = esNino
                          ? (item as Nino).nombreCompleto
                          : (item as Acudiente).nombreCompleto;
                      return ListTile(
                        leading: Icon(
                          esNino ? Icons.child_care : Icons.person,
                          color: AppColors.azulMarino,
                        ),
                        title: Text(nombre),
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => esNino
                              ? NinoDetalleSheet(
                                  nino: item as Nino,
                                  usuario: usuario,
                                )
                              : AcudienteDetalleSheet(
                                  acudiente: item as Acudiente,
                                  usuario: usuario,
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
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

        final porGrupo = <String, int>{for (final g in gruposEdad) g: 0};
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
            else
              _GraficasResponsivas(
                graficas: [
                  _GraficaBarras(titulo: 'Por grupo de edad', datos: porGrupo),
                  _GraficaBarras(
                    titulo: 'Por servicio',
                    datos: porServicio,
                    etiquetaCorta: (k) => _servicioCorto[k] ?? k,
                  ),
                ],
              ),
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
            final primerasAsistencias = primeraAsistenciaPorNino.values.toList()
              ..sort();
            final crecimientoAcumulado = <double>[
              for (final finDeMes in mesesEnRango.map((m) => _sumarMeses(m, 1)))
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

            return _GraficasResponsivas(
              graficas: [
                _GraficaLinea(
                  titulo: 'Crecimiento de niños registrados (acumulado)',
                  etiquetasX: mesesEnRango.map(_etiquetaMes).toList(),
                  valores: crecimientoAcumulado,
                ),
                _GraficaBarras(
                  titulo: 'Asistencia por mes',
                  datos: asistenciaPorMes,
                ),
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
          Icon(icono, color: destacar ? AppColors.rojo : AppColors.azulMarino),
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

/// Cada cuántas etiquetas mostrar una en el eje X, para que no se
/// encimen sin importar cuántos meses/categorías haya ni el ancho de
/// pantalla (2026-08-19, pedido de Rafael) — en vez de mostrarlas
/// TODAS siempre. Estima ~45px por etiqueta (abreviaciones cortas tipo
/// "ene" o "Dom 1°" a `bodySmall`) y salta las que no quepan.
int _pasoEtiquetas(double anchoDisponible, int totalEtiquetas) {
  if (totalEtiquetas <= 1) return 1;
  final maxVisibles = (anchoDisponible / 45).floor().clamp(2, totalEtiquetas);
  return (totalEtiquetas / maxVisibles).ceil().clamp(1, totalEtiquetas);
}

FlTitlesData _ejesConEtiquetas(
  BuildContext context,
  List<String> etiquetasX,
  double techo, {
  int paso = 1,
}) {
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
          if (paso > 1 && i % paso != 0) return const SizedBox.shrink();
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

/// Acomoda una lista de tarjetas de gráfica en 2 columnas cuando hay
/// espacio de sobra (escritorio/tablet ancho) y en una sola columna
/// apiladas en pantallas angostas (celular) — 2026-08-19, pedido de
/// Rafael de que las gráficas se vean bien "en cualquier dispositivo".
class _GraficasResponsivas extends StatelessWidget {
  final List<Widget> graficas;
  const _GraficasResponsivas({required this.graficas});

  static const _espaciado = 20.0;
  static const _anchoMinParaDosColumnas = 700.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _anchoMinParaDosColumnas) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < graficas.length; i++) ...[
                if (i > 0) const SizedBox(height: _espaciado),
                graficas[i],
              ],
            ],
          );
        }
        final anchoColumna = (constraints.maxWidth - _espaciado) / 2;
        return Wrap(
          spacing: _espaciado,
          runSpacing: _espaciado,
          children: [
            for (final g in graficas) SizedBox(width: anchoColumna, child: g),
          ],
        );
      },
    );
  }
}

/// Gráfica de barras genérica: una barra por cada llave de [datos], en el
/// mismo orden en que se insertaron. Un solo color de marca — no hace
/// falta codificar identidad por color porque cada barra ya lleva su
/// propia etiqueta en el eje X. Interactiva: tocar (o pasar el mouse en
/// escritorio/web) una barra muestra su valor exacto en un tooltip y
/// resalta esa barra en amarillo (2026-08-19, pedido de Rafael).
class _GraficaBarras extends StatefulWidget {
  final String titulo;
  final Map<String, int> datos;
  final String Function(String llave)? etiquetaCorta;

  const _GraficaBarras({
    required this.titulo,
    required this.datos,
    this.etiquetaCorta,
  });

  @override
  State<_GraficaBarras> createState() => _GraficaBarrasState();
}

class _GraficaBarrasState extends State<_GraficaBarras> {
  int? _indiceResaltado;

  @override
  Widget build(BuildContext context) {
    final llaves = widget.datos.keys.toList();
    final maxValor = widget.datos.values.isEmpty
        ? 0
        : widget.datos.values.reduce((a, b) => a > b ? a : b);
    final techo = maxValor == 0 ? 1.0 : (maxValor * 1.2);
    final etiquetasX = [
      for (final k in llaves) widget.etiquetaCorta?.call(k) ?? k,
    ];

    return _tarjetaGrafica(
      context,
      titulo: widget.titulo,
      grafica: LayoutBuilder(
        builder: (context, constraints) => BarChart(
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
            titlesData: _ejesConEtiquetas(
              context,
              etiquetasX,
              techo,
              paso: _pasoEtiquetas(constraints.maxWidth, etiquetasX.length),
            ),
            barTouchData: BarTouchData(
              touchCallback: (evento, respuesta) {
                final indice = respuesta?.spot?.touchedBarGroupIndex;
                final nuevoIndice = (indice != null && indice >= 0)
                    ? indice
                    : null;
                if (nuevoIndice != _indiceResaltado) {
                  setState(() => _indiceResaltado = nuevoIndice);
                }
              },
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
                      toY: (widget.datos[llaves[i]] ?? 0).toDouble(),
                      color: i == _indiceResaltado
                          ? AppColors.amarillo
                          : AppColors.azulMarino,
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
      grafica: LayoutBuilder(
        builder: (context, constraints) => LineChart(
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
            titlesData: _ejesConEtiquetas(
              context,
              etiquetasX,
              techo,
              paso: _pasoEtiquetas(constraints.maxWidth, etiquetasX.length),
            ),
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
                              radius: 6,
                              color: AppColors.amarillo,
                              strokeWidth: 2,
                              strokeColor: AppColors.azulMarino,
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
      ),
    );
  }
}

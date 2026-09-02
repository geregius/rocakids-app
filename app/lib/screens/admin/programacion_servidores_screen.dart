import 'package:flutter/material.dart';

import '../../models/grupo_servidores.dart';
import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/confirmar_eliminar.dart';

/// Valor centinela para la opción "+ Nueva categoría..." en el
/// dropdown de `_GrupoServidoresSheet` — nunca puede coincidir con un
/// nombre real de categoría porque ninguna categoría real empieza así.
const _nuevaCategoriaCentinela = ' _nueva_categoria';

/// "Programación de Servidores" (2026-08-31, pedido de Rafael) — crear
/// grupos/equipos de servidores dentro de una categoría (las
/// categorías también se crean desde la app, ver
/// [CategoriaProgramacion]) y asignarles integrantes, más (2026-09-02,
/// etapa 2) la rotación automática de quién le toca en cada ocasión.
/// **Solo administrador y líder de ministerio**
/// (`RolUsuario.puedeGestionarProgramacion`) — a propósito MÁS
/// ACOTADO que "Gestión de Servidores" (columna no entra acá, pedido
/// explícito de Rafael).
///
/// Dos pestañas:
/// - **"Grupos"**: crear/editar/eliminar categorías y grupos, asignar
///   servidores, reordenar la rotación dentro de cada categoría.
/// - **"Próximos Servicios"**: para cada categoría, quién le toca en
///   la próxima ocasión — calculado solo si la categoría es `semanal`
///   (ej. Domingos, cada domingo un grupo distinto, en orden, a partir
///   de un punto de partida que se fija una sola vez); programado a
///   mano si es `manual` (ej. Casa2/Ayunos, no caen en un día fijo —
///   el sistema sugiere el siguiente grupo en el orden, Rafael
///   confirma o cambia).
class ProgramacionServidoresScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const ProgramacionServidoresScreen({super.key, required this.usuario});

  @override
  State<ProgramacionServidoresScreen> createState() =>
      _ProgramacionServidoresScreenState();
}

class _ProgramacionServidoresScreenState
    extends State<ProgramacionServidoresScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  late Future<List<UsuarioApp>> _servidoresFuture;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _servidoresFuture = _authService.obtenerTodosLosServidoresActivos();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _abrirFormularioGrupo({
    List<UsuarioApp> servidores = const [],
    List<CategoriaProgramacion> categorias = const [],
    List<GrupoServidores> gruposExistentes = const [],
    GrupoServidores? grupo,
    String? categoriaInicial,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GrupoServidoresSheet(
        servidores: servidores,
        categorias: categorias,
        gruposExistentes: gruposExistentes,
        grupo: grupo,
        categoriaInicial: categoriaInicial,
      ),
    );
  }

  Future<void> _crearCategoria() async {
    final resultado = await _pedirNuevaCategoria(context);
    if (resultado == null) return;
    try {
      await _authService.crearCategoriaProgramacion(
        resultado.nombre,
        tipoRotacion: resultado.tipoRotacion,
        diaSemana: resultado.diaSemana,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la categoría: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Programación de Servidores',
      construirPantalla: () =>
          ProgramacionServidoresScreen(usuario: widget.usuario),
      floatingActionButton: FutureBuilder<List<UsuarioApp>>(
        future: _servidoresFuture,
        builder: (context, snapshotServidores) {
          return StreamBuilder<List<CategoriaProgramacion>>(
            stream: _authService.listarCategoriasProgramacion(),
            builder: (context, snapshotCategorias) {
              return StreamBuilder<List<GrupoServidores>>(
                stream: _authService.listarGruposServidores(),
                builder: (context, snapshotGrupos) {
                  final servidores = snapshotServidores.data ?? [];
                  final categorias = snapshotCategorias.data ?? [];
                  final grupos = snapshotGrupos.data ?? [];
                  return FloatingActionButton.extended(
                    onPressed: () => _abrirFormularioGrupo(
                      servidores: servidores,
                      categorias: categorias,
                      gruposExistentes: grupos,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear grupo'),
                  );
                },
              );
            },
          );
        },
      ),
      body: (context) => Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.azulMarino,
            tabs: const [
              Tab(text: 'Grupos'),
              Tab(text: 'Próximos Servicios'),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<UsuarioApp>>(
              future: _servidoresFuture,
              builder: (context, snapshotServidores) {
                if (snapshotServidores.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshotServidores.hasError) {
                  return Center(child: Text('Error: ${snapshotServidores.error}'));
                }
                final servidores = snapshotServidores.data ?? [];
                final servidoresPorId = {for (final s in servidores) s.uid: s};

                return StreamBuilder<List<CategoriaProgramacion>>(
                  stream: _authService.listarCategoriasProgramacion(),
                  builder: (context, snapshotCategorias) {
                    if (snapshotCategorias.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshotCategorias.hasError) {
                      return Center(child: Text('Error: ${snapshotCategorias.error}'));
                    }
                    final categorias = snapshotCategorias.data ?? [];

                    return StreamBuilder<List<GrupoServidores>>(
                      stream: _authService.listarGruposServidores(),
                      builder: (context, snapshotGrupos) {
                        if (snapshotGrupos.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshotGrupos.hasError) {
                          return Center(child: Text('Error: ${snapshotGrupos.error}'));
                        }
                        final grupos = <GrupoServidores>[...(snapshotGrupos.data ?? [])]
                          ..sort((a, b) => a.orden.compareTo(b.orden));
                        final porCategoria = <String, List<GrupoServidores>>{};
                        for (final g in grupos) {
                          porCategoria.putIfAbsent(g.categoria, () => []).add(g);
                        }

                        return StreamBuilder<List<ServicioProgramado>>(
                          stream: _authService.listarServiciosProgramados(),
                          builder: (context, snapshotServicios) {
                            final servicios = snapshotServicios.data ?? [];

                            return TabBarView(
                              controller: _tabController,
                              children: [
                                _GruposTab(
                                  categorias: categorias,
                                  porCategoria: porCategoria,
                                  servidoresPorId: servidoresPorId,
                                  onCrearCategoria: _crearCategoria,
                                  onAgregarGrupo: (categoria) => _abrirFormularioGrupo(
                                    servidores: servidores,
                                    categorias: categorias,
                                    gruposExistentes: grupos,
                                    categoriaInicial: categoria,
                                  ),
                                  onEditarGrupo: (g) => _abrirFormularioGrupo(
                                    servidores: servidores,
                                    categorias: categorias,
                                    gruposExistentes: grupos,
                                    grupo: g,
                                    categoriaInicial: g.categoria,
                                  ),
                                ),
                                _ProximosServiciosTab(
                                  categorias: categorias,
                                  porCategoria: porCategoria,
                                  servicios: servicios,
                                  servidoresPorId: servidoresPorId,
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NuevaCategoria {
  final String nombre;
  final TipoRotacion tipoRotacion;
  final int? diaSemana;
  const _NuevaCategoria(this.nombre, this.tipoRotacion, this.diaSemana);
}

/// Diálogo para crear una categoría nueva — nombre, si es semanal
/// (día fijo, rotación automática) o manual (se programa cada
/// ocasión, ej. Casa2/Ayunos) y, si es semanal, qué día de la semana.
/// Reusado desde el botón "Nueva categoría" de la pestaña "Grupos" y
/// desde la opción "+ Nueva categoría..." del dropdown al crear/editar
/// un grupo. Devuelve `null` si se canceló.
Future<_NuevaCategoria?> _pedirNuevaCategoria(BuildContext context) {
  final controller = TextEditingController();
  var tipo = TipoRotacion.semanal;
  var dia = DateTime.sunday;

  return showDialog<_NuevaCategoria>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Ej. Domingos, Retiro...'),
            ),
            const SizedBox(height: 16),
            RadioGroup<TipoRotacion>(
              groupValue: tipo,
              onChanged: (v) => setState(() => tipo = v!),
              child: const Column(
                children: [
                  RadioListTile<TipoRotacion>(
                    contentPadding: EdgeInsets.zero,
                    value: TipoRotacion.semanal,
                    title: Text('Cae en un día fijo cada semana'),
                    subtitle: Text('El sistema rota los grupos solo, en orden'),
                  ),
                  RadioListTile<TipoRotacion>(
                    contentPadding: EdgeInsets.zero,
                    value: TipoRotacion.manual,
                    title: Text('No tiene un día fijo (ej. Casa2, Ayunos)'),
                    subtitle: Text('Se programa cada ocasión a mano'),
                  ),
                ],
              ),
            ),
            if (tipo == TipoRotacion.semanal) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: dia,
                decoration: const InputDecoration(labelText: 'Día de la semana'),
                items: [
                  for (var d = 1; d <= 7; d++)
                    DropdownMenuItem(value: d, child: Text(nombreDiaSemana(d))),
                ],
                onChanged: (v) => setState(() => dia = v!),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final nombre = controller.text.trim();
              if (nombre.isEmpty) return;
              Navigator.of(context).pop(
                _NuevaCategoria(nombre, tipo, tipo == TipoRotacion.semanal ? dia : null),
              );
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    ),
  ).then((r) {
    controller.dispose();
    return r;
  });
}

class _GruposTab extends StatelessWidget {
  final List<CategoriaProgramacion> categorias;
  final Map<String, List<GrupoServidores>> porCategoria;
  final Map<String, UsuarioApp> servidoresPorId;
  final VoidCallback onCrearCategoria;
  final ValueChanged<String> onAgregarGrupo;
  final ValueChanged<GrupoServidores> onEditarGrupo;

  const _GruposTab({
    required this.categorias,
    required this.porCategoria,
    required this.servidoresPorId,
    required this.onCrearCategoria,
    required this.onAgregarGrupo,
    required this.onEditarGrupo,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        OutlinedButton.icon(
          onPressed: onCrearCategoria,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Nueva categoría'),
        ),
        const SizedBox(height: 16),
        if (categorias.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no hay ninguna categoría creada.'),
          )
        else
          for (final categoria in categorias)
            _SeccionCategoria(
              categoria: categoria,
              grupos: porCategoria[categoria.nombre] ?? const [],
              servidoresPorId: servidoresPorId,
              onAgregar: () => onAgregarGrupo(categoria.nombre),
              onEditar: onEditarGrupo,
            ),
      ],
    );
  }
}

class _SeccionCategoria extends StatelessWidget {
  final CategoriaProgramacion categoria;
  final List<GrupoServidores> grupos;
  final Map<String, UsuarioApp> servidoresPorId;
  final VoidCallback onAgregar;
  final ValueChanged<GrupoServidores> onEditar;

  const _SeccionCategoria({
    required this.categoria,
    required this.grupos,
    required this.servidoresPorId,
    required this.onAgregar,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final subtitulo = categoria.tipoRotacion == TipoRotacion.semanal
        ? 'Cada ${nombreDiaSemana(categoria.diaSemana ?? DateTime.sunday)}'
        : 'Se programa cada ocasión';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${categoria.nombre} (${grupos.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.azulMarino,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(subtitulo, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                onPressed: onAgregar,
                icon: const Icon(Icons.add_circle_outline, color: AppColors.azulMarino),
                tooltip: 'Crear grupo en ${categoria.nombre}',
              ),
            ],
          ),
          children: [
            const Divider(height: 1),
            if (grupos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Todavía no hay grupos en esta categoría.'),
                ),
              )
            else
              for (var i = 0; i < grupos.length; i++)
                _TarjetaGrupo(
                  grupo: grupos[i],
                  servidoresPorId: servidoresPorId,
                  onEditar: () => onEditar(grupos[i]),
                  onSubir: i > 0
                      ? () => AuthService().intercambiarOrdenGrupos(grupos[i], grupos[i - 1])
                      : null,
                  onBajar: i < grupos.length - 1
                      ? () => AuthService().intercambiarOrdenGrupos(grupos[i], grupos[i + 1])
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaGrupo extends StatelessWidget {
  final GrupoServidores grupo;
  final Map<String, UsuarioApp> servidoresPorId;
  final VoidCallback onEditar;
  final VoidCallback? onSubir;
  final VoidCallback? onBajar;

  const _TarjetaGrupo({
    required this.grupo,
    required this.servidoresPorId,
    required this.onEditar,
    required this.onSubir,
    required this.onBajar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(grupo.nombre),
        subtitle: Text(_nombresDe(grupo.fkIdsServidores, servidoresPorId)),
        onTap: onEditar,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${grupo.fkIdsServidores.length}'),
            IconButton(
              onPressed: onSubir,
              icon: const Icon(Icons.arrow_upward),
              iconSize: 18,
              tooltip: 'Mover antes en la rotación',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onBajar,
              icon: const Icon(Icons.arrow_downward),
              iconSize: 18,
              tooltip: 'Mover después en la rotación',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  String _nombresDe(List<String> ids, Map<String, UsuarioApp> servidoresPorId) {
    if (ids.isEmpty) return 'Sin servidores asignados todavía';
    final nombres = ids
        .map((id) => servidoresPorId[id]?.nombreCompleto)
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    return nombres.isEmpty ? '${ids.length} servidor(es)' : nombres.join(', ');
  }
}

class _ProximosServiciosTab extends StatelessWidget {
  final List<CategoriaProgramacion> categorias;
  final Map<String, List<GrupoServidores>> porCategoria;
  final List<ServicioProgramado> servicios;
  final Map<String, UsuarioApp> servidoresPorId;

  const _ProximosServiciosTab({
    required this.categorias,
    required this.porCategoria,
    required this.servicios,
    required this.servidoresPorId,
  });

  @override
  Widget build(BuildContext context) {
    if (categorias.isEmpty) {
      return const Center(child: Text('Todavía no hay ninguna categoría creada.'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final categoria in categorias)
          _TarjetaProximoServicio(
            categoria: categoria,
            grupos: porCategoria[categoria.nombre] ?? const [],
            servicios: servicios.where((s) => s.categoria == categoria.nombre).toList(),
            servidoresPorId: servidoresPorId,
          ),
      ],
    );
  }
}

class _TarjetaProximoServicio extends StatelessWidget {
  final CategoriaProgramacion categoria;
  final List<GrupoServidores> grupos;
  final List<ServicioProgramado> servicios;
  final Map<String, UsuarioApp> servidoresPorId;

  const _TarjetaProximoServicio({
    required this.categoria,
    required this.grupos,
    required this.servicios,
    required this.servidoresPorId,
  });

  Future<void> _configurarRotacion(BuildContext context) async {
    if (grupos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea al menos un grupo en esta categoría.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfigurarRotacionSheet(categoria: categoria, grupos: grupos),
    );
  }

  Future<void> _programarServicio(BuildContext context, {ServicioProgramado? existente}) async {
    if (grupos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea al menos un grupo en esta categoría.')),
      );
      return;
    }
    final ordenados = [...servicios]..sort((a, b) => b.fecha.compareTo(a.fecha));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProgramarServicioSheet(
        categoria: categoria,
        grupos: grupos,
        ultimoServicio: ordenados.isEmpty ? null : ordenados.first,
        existente: existente,
      ),
    );
  }

  String _nombresDe(List<String> ids) {
    if (ids.isEmpty) return 'Sin servidores asignados';
    final nombres = ids
        .map((id) => servidoresPorId[id]?.nombreCompleto)
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    return nombres.isEmpty ? '${ids.length} servidor(es)' : nombres.join(', ');
  }

  String _fechaTexto(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  @override
  Widget build(BuildContext context) {
    final esSemanal = categoria.tipoRotacion == TipoRotacion.semanal;
    Widget contenido;
    List<Widget> acciones;

    if (esSemanal) {
      final diaSemana = categoria.diaSemana ?? DateTime.sunday;
      final fechaObjetivo = proximaFechaDia(diaSemana);
      final tieneReferencia = categoria.fechaReferenciaRotacion != null &&
          categoria.grupoReferenciaId != null;
      final grupo = tieneReferencia
          ? grupoQueSirve(
              gruposOrdenados: grupos,
              fechaReferencia: categoria.fechaReferenciaRotacion!,
              grupoReferenciaId: categoria.grupoReferenciaId!,
              fechaObjetivo: fechaObjetivo,
            )
          : null;
      contenido = grupo != null
          ? _FilaResultado(
              titulo: 'Próximo ${nombreDiaSemana(diaSemana)} ${_fechaTexto(fechaObjetivo)}',
              grupoNombre: grupo.nombre,
              integrantes: _nombresDe(grupo.fkIdsServidores),
            )
          : Text(
              tieneReferencia
                  ? 'El grupo configurado como punto de partida ya no existe — vuelve a configurarlo.'
                  : 'Todavía no se configuró desde qué grupo arranca la rotación.',
              style: const TextStyle(color: AppColors.rojo),
            );
      acciones = [
        OutlinedButton(
          onPressed: () => _configurarRotacion(context),
          child: Text(tieneReferencia ? 'Cambiar punto de partida' : 'Elegir grupo de partida'),
        ),
      ];
    } else {
      final hoy = DateTime.now();
      final proximos = servicios.where((s) => !s.fecha.isBefore(DateTime(hoy.year, hoy.month, hoy.day))).toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
      final proximo = proximos.isEmpty ? null : proximos.first;
      GrupoServidores? grupo;
      if (proximo != null) {
        for (final g in grupos) {
          if (g.id == proximo.grupoId) {
            grupo = g;
            break;
          }
        }
      }
      contenido = proximo == null
          ? const Text('Todavía no hay ningún servicio programado.')
          : _FilaResultado(
              titulo: _fechaTexto(proximo.fecha),
              grupoNombre: grupo?.nombre ?? '(grupo eliminado)',
              integrantes: grupo == null ? '' : _nombresDe(grupo.fkIdsServidores),
            );
      acciones = [
        OutlinedButton(
          onPressed: () => _programarServicio(context, existente: proximo),
          child: Text(proximo == null ? 'Programar servicio' : 'Reprogramar'),
        ),
        if (proximo != null)
          TextButton(
            onPressed: () async {
              final confirmado = await confirmarEliminar(
                context,
                nombre: 'El servicio de ${categoria.nombre} del ${_fechaTexto(proximo.fecha)}',
              );
              if (confirmado) {
                await AuthService().eliminarServicioProgramado(proximo.id);
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.rojo),
            child: const Text('Quitar'),
          ),
      ];
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              categoria.nombre,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.azulMarino,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            contenido,
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: acciones),
          ],
        ),
      ),
    );
  }
}

class _FilaResultado extends StatelessWidget {
  final String titulo;
  final String grupoNombre;
  final String integrantes;

  const _FilaResultado({
    required this.titulo,
    required this.grupoNombre,
    required this.integrantes,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.bodySmall),
        Text(grupoNombre, style: Theme.of(context).textTheme.titleLarge),
        if (integrantes.isNotEmpty)
          Text(integrantes, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Fija (o cambia) el punto de partida de la rotación automática de
/// una categoría `semanal`: "el [fecha] sirve [grupo]". El selector de
/// fecha solo deja elegir fechas que caigan en el día de la semana de
/// la categoría (`selectableDayPredicate`), para no poder configurar
/// por error un punto de partida que no tenga sentido.
class _ConfigurarRotacionSheet extends StatefulWidget {
  final CategoriaProgramacion categoria;
  final List<GrupoServidores> grupos;

  const _ConfigurarRotacionSheet({required this.categoria, required this.grupos});

  @override
  State<_ConfigurarRotacionSheet> createState() => _ConfigurarRotacionSheetState();
}

class _ConfigurarRotacionSheetState extends State<_ConfigurarRotacionSheet> {
  late DateTime _fecha;
  late String _grupoId;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final diaSemana = widget.categoria.diaSemana ?? DateTime.sunday;
    _fecha = widget.categoria.fechaReferenciaRotacion ?? proximaFechaDia(diaSemana);
    _grupoId = widget.categoria.grupoReferenciaId ?? widget.grupos.first.id;
    if (!widget.grupos.any((g) => g.id == _grupoId)) {
      _grupoId = widget.grupos.first.id;
    }
  }

  Future<void> _elegirFecha() async {
    final diaSemana = widget.categoria.diaSemana ?? DateTime.sunday;
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (d) => d.weekday == diaSemana,
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await AuthService().configurarRotacionCategoria(
        categoriaId: widget.categoria.id,
        fecha: _fecha,
        grupoId: _grupoId,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    }
  }

  String _fechaTexto(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Punto de partida de ${widget.categoria.nombre}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('¿Qué grupo sirve en la fecha que elijas? De ahí en adelante la rotación sigue sola.'),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fecha'),
            subtitle: Text(_fechaTexto(_fecha)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _elegirFecha,
          ),
          DropdownButtonFormField<String>(
            initialValue: _grupoId,
            decoration: const InputDecoration(labelText: 'Grupo que sirve esa fecha'),
            items: widget.grupos
                .map((g) => DropdownMenuItem(value: g.id, child: Text(g.nombre)))
                .toList(),
            onChanged: (v) => setState(() => _grupoId = v!),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

/// Programa (o corrige) una ocasión de una categoría `manual` (Casa2,
/// Ayunos): fecha + grupo. Sugiere el siguiente grupo en la rotación a
/// partir de [ultimoServicio] (el más reciente ya programado de esa
/// categoría), Rafael puede cambiarlo antes de guardar.
class _ProgramarServicioSheet extends StatefulWidget {
  final CategoriaProgramacion categoria;
  final List<GrupoServidores> grupos;
  final ServicioProgramado? ultimoServicio;
  final ServicioProgramado? existente;

  const _ProgramarServicioSheet({
    required this.categoria,
    required this.grupos,
    required this.ultimoServicio,
    this.existente,
  });

  @override
  State<_ProgramarServicioSheet> createState() => _ProgramarServicioSheetState();
}

class _ProgramarServicioSheetState extends State<_ProgramarServicioSheet> {
  late DateTime _fecha;
  late String _grupoId;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _fecha = widget.existente?.fecha ?? DateTime.now().add(const Duration(days: 7));
    final sugerido = widget.existente?.grupoId ??
        siguienteGrupoSugerido(
          gruposOrdenados: widget.grupos,
          ultimoServicio: widget.ultimoServicio,
        )?.id;
    _grupoId = sugerido ?? widget.grupos.first.id;
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      if (widget.existente != null) {
        await AuthService().eliminarServicioProgramado(widget.existente!.id);
      }
      await AuthService().programarServicio(
        categoria: widget.categoria.nombre,
        fecha: _fecha,
        grupoId: _grupoId,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    }
  }

  String _fechaTexto(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Programar ${widget.categoria.nombre}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fecha del servicio'),
            subtitle: Text(_fechaTexto(_fecha)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _elegirFecha,
          ),
          DropdownButtonFormField<String>(
            initialValue: _grupoId,
            decoration: const InputDecoration(labelText: 'Grupo que sirve (sugerido primero)'),
            items: widget.grupos
                .map((g) => DropdownMenuItem(value: g.id, child: Text(g.nombre)))
                .toList(),
            onChanged: (v) => setState(() => _grupoId = v!),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _GrupoServidoresSheet extends StatefulWidget {
  final List<UsuarioApp> servidores;
  final List<CategoriaProgramacion> categorias;
  final List<GrupoServidores> gruposExistentes;
  final GrupoServidores? grupo;
  final String? categoriaInicial;

  const _GrupoServidoresSheet({
    required this.servidores,
    required this.categorias,
    required this.gruposExistentes,
    this.grupo,
    this.categoriaInicial,
  });

  @override
  State<_GrupoServidoresSheet> createState() => _GrupoServidoresSheetState();
}

class _GrupoServidoresSheetState extends State<_GrupoServidoresSheet> {
  late final TextEditingController _nombreController;
  late String _categoria;
  late Set<String> _seleccionados;
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  bool _guardando = false;
  bool _eliminando = false;
  String? _error;

  bool get _editando => widget.grupo != null;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.grupo?.nombre ?? '');
    _categoria = widget.grupo?.categoria ??
        widget.categoriaInicial ??
        (widget.categorias.isNotEmpty ? widget.categorias.first.nombre : '');
    _seleccionados = {...?widget.grupo?.fkIdsServidores};
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _busquedaController.dispose();
    super.dispose();
  }

  List<UsuarioApp> get _servidoresFiltrados {
    if (_busqueda.trim().isEmpty) return widget.servidores;
    final q = _busqueda.trim().toLowerCase();
    return widget.servidores
        .where((s) => s.nombreCompleto.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _elegirCategoria(String? valor) async {
    if (valor == _nuevaCategoriaCentinela) {
      final resultado = await _pedirNuevaCategoria(context);
      if (resultado == null || !mounted) return;
      try {
        await AuthService().crearCategoriaProgramacion(
          resultado.nombre,
          tipoRotacion: resultado.tipoRotacion,
          diaSemana: resultado.diaSemana,
        );
        setState(() => _categoria = resultado.nombre);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo crear la categoría: $e')),
          );
        }
      }
      return;
    }
    setState(() => _categoria = valor!);
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ponle un nombre al grupo.');
      return;
    }
    if (_categoria.isEmpty) {
      setState(() => _error = 'Elige o crea una categoría.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_editando) {
        await AuthService().editarGrupoServidores(
          id: widget.grupo!.id,
          categoria: _categoria,
          nombre: nombre,
          fkIdsServidores: _seleccionados.toList(),
          orden: widget.grupo!.orden,
        );
      } else {
        final yaEnCategoria =
            widget.gruposExistentes.where((g) => g.categoria == _categoria).length;
        await AuthService().crearGrupoServidores(
          categoria: _categoria,
          nombre: nombre,
          fkIdsServidores: _seleccionados.toList(),
          orden: yaEnCategoria,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'No se pudo guardar: $e';
        _guardando = false;
      });
    }
  }

  Future<void> _eliminar() async {
    final confirmado = await confirmarEliminar(context, nombre: widget.grupo!.nombre);
    if (!confirmado) return;
    setState(() => _eliminando = true);
    try {
      await AuthService().eliminarGrupoServidores(widget.grupo!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _eliminando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // La categoría del grupo que se está editando puede no venir en
    // `widget.categorias` todavía (ej. si el stream de categorías no
    // ha refrescado) — se agrega igual para que el dropdown no truene
    // por un `value` sin `item` correspondiente.
    final nombresCategorias = {
      ...widget.categorias.map((c) => c.nombre),
      if (_categoria.isNotEmpty) _categoria,
    }.toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            children: [
              Text(
                _editando ? 'Editar grupo' : 'Crear grupo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _categoria.isNotEmpty ? _categoria : null,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  ...nombresCategorias.map(
                    (c) => DropdownMenuItem(value: c, child: Text(c)),
                  ),
                  const DropdownMenuItem(
                    value: _nuevaCategoriaCentinela,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 18, color: AppColors.azulMarino),
                        SizedBox(width: 6),
                        Text('Nueva categoría...', style: TextStyle(color: AppColors.azulMarino)),
                      ],
                    ),
                  ),
                ],
                onChanged: _elegirCategoria,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre del grupo'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),
              Text(
                'Servidores (${_seleccionados.length} seleccionados)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _busquedaController,
                decoration: InputDecoration(
                  hintText: 'Buscar servidor por nombre...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() => _busqueda = v),
              ),
              const SizedBox(height: 4),
              if (_servidoresFiltrados.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No se encontró ningún servidor.'),
                )
              else
                ..._servidoresFiltrados.map(
                  (s) => CheckboxListTile(
                    value: _seleccionados.contains(s.uid),
                    title: Text(s.nombreCompleto.isNotEmpty ? s.nombreCompleto : s.correo),
                    subtitle: Text(s.rol.etiqueta),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (marcado) => setState(() {
                      if (marcado ?? false) {
                        _seleccionados.add(s.uid);
                      } else {
                        _seleccionados.remove(s.uid);
                      }
                    }),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.rojo)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar'),
              ),
              if (_editando) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _eliminando ? null : _eliminar,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.rojo),
                  icon: _eliminando
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text('Eliminar grupo'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

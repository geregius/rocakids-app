import 'package:flutter/material.dart';

import '../../models/grupo_servidores.dart';
import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/confirmar_eliminar.dart';

/// "Programación de Servidores" (2026-08-31, pedido de Rafael) — crear
/// grupos/equipos de servidores dentro de una categoría fija
/// ([categoriasProgramacion]: Domingos, Miércoles, Casa2, Ayunos) y
/// asignarles integrantes, para poder organizar turnos más adelante.
/// **Solo administrador y líder de ministerio**
/// (`RolUsuario.puedeGestionarProgramacion`) — a propósito MÁS ACOTADO
/// que "Gestión de Servidores" (columna no entra acá, pedido explícito
/// de Rafael). Primera versión: solo crear/editar/eliminar grupos y
/// asignar servidores — la programación de turnos en sí (quién sirve
/// qué día) queda para una siguiente etapa.
class ProgramacionServidoresScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const ProgramacionServidoresScreen({super.key, required this.usuario});

  @override
  State<ProgramacionServidoresScreen> createState() =>
      _ProgramacionServidoresScreenState();
}

class _ProgramacionServidoresScreenState
    extends State<ProgramacionServidoresScreen> {
  final _authService = AuthService();
  late Future<List<UsuarioApp>> _servidoresFuture;

  @override
  void initState() {
    super.initState();
    _servidoresFuture = _authService.obtenerTodosLosServidoresActivos();
  }

  Future<void> _abrirFormulario({
    List<UsuarioApp> servidores = const [],
    GrupoServidores? grupo,
    String? categoriaInicial,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GrupoServidoresSheet(
        servidores: servidores,
        grupo: grupo,
        categoriaInicial: categoriaInicial,
      ),
    );
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
        builder: (context, snapshot) {
          final servidores = snapshot.data ?? [];
          return FloatingActionButton.extended(
            onPressed: () => _abrirFormulario(servidores: servidores),
            icon: const Icon(Icons.add),
            label: const Text('Crear grupo'),
          );
        },
      ),
      body: (context) => FutureBuilder<List<UsuarioApp>>(
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

          return StreamBuilder<List<GrupoServidores>>(
            stream: _authService.listarGruposServidores(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final grupos = snapshot.data ?? [];
              final porCategoria = <String, List<GrupoServidores>>{};
              for (final g in grupos) {
                porCategoria.putIfAbsent(g.categoria, () => []).add(g);
              }
              for (final lista in porCategoria.values) {
                lista.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                children: [
                  for (final categoria in categoriasProgramacion)
                    _SeccionCategoria(
                      categoria: categoria,
                      grupos: porCategoria[categoria] ?? const [],
                      servidoresPorId: servidoresPorId,
                      onAgregar: () => _abrirFormulario(
                        servidores: servidores,
                        categoriaInicial: categoria,
                      ),
                      onEditar: (g) => _abrirFormulario(
                        servidores: servidores,
                        grupo: g,
                        categoriaInicial: g.categoria,
                      ),
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

class _SeccionCategoria extends StatelessWidget {
  final String categoria;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$categoria (${grupos.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.azulMarino,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: onAgregar,
                icon: const Icon(Icons.add_circle_outline, color: AppColors.azulMarino),
                tooltip: 'Crear grupo en $categoria',
              ),
            ],
          ),
          if (grupos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Todavía no hay grupos en esta categoría.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ...grupos.map(
              (g) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(g.nombre),
                  subtitle: Text(_nombresDe(g.fkIdsServidores, servidoresPorId)),
                  trailing: Text('${g.fkIdsServidores.length}'),
                  onTap: () => onEditar(g),
                ),
              ),
            ),
        ],
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

class _GrupoServidoresSheet extends StatefulWidget {
  final List<UsuarioApp> servidores;
  final GrupoServidores? grupo;
  final String? categoriaInicial;

  const _GrupoServidoresSheet({
    required this.servidores,
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
        categoriasProgramacion.first;
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

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ponle un nombre al grupo.');
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
        );
      } else {
        await AuthService().crearGrupoServidores(
          categoria: _categoria,
          nombre: nombre,
          fkIdsServidores: _seleccionados.toList(),
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
                initialValue: _categoria,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: categoriasProgramacion
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _categoria = v!),
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

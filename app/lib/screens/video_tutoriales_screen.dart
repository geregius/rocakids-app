import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/manual_contenido.dart';
import '../models/usuario_app.dart';
import '../models/video_tutorial.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/youtube_helper.dart';
import '../widgets/app_shell.dart';
import '../widgets/confirmar_eliminar.dart';

String _tituloManualPara(AudienciaManual audiencia) =>
    manualCapitulos.firstWhere((c) => c.audiencia == audiencia).titulo;

/// "Video Tutoriales" (2026-08-22, pedido de Rafael): la otra mitad de
/// "Manual de usuario" — los mismos temas, en video en vez de texto+
/// capturas. Solo se guarda el enlace de YouTube y un par de campos de
/// texto en Firestore (`videos_tutoriales`); el video en sí lo sigue
/// sirviendo YouTube — RocaKids nunca lo sube ni lo aloja, así que esto
/// no pesa nada distinto a cualquier otra colección chica de la app.
///
/// Mismas 3 pestañas por audiencia que el manual en PDF (reutiliza
/// `manualCapitulos` para los títulos, para que digan lo mismo en
/// ambos lados). Un video puede aplicar a más de una audiencia a la vez.
/// Solo el administrador puede agregar/editar/borrar videos — Rafael
/// copia los enlaces de YouTube él mismo, la app solo guarda el enlace y
/// trae el título real desde YouTube (`utils/youtube_helper.dart`).
class VideoTutorialesScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const VideoTutorialesScreen({super.key, required this.usuario});

  @override
  State<VideoTutorialesScreen> createState() => _VideoTutorialesScreenState();
}

class _VideoTutorialesScreenState extends State<VideoTutorialesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: AudienciaManual.values.length,
      vsync: this,
      initialIndex: widget.usuario.rol.esRolDeServidor ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _abrirFormulario({VideoTutorial? video}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormularioVideoSheet(video: video),
    );
  }

  Future<void> _eliminar(VideoTutorial video) async {
    final confirmado = await confirmarEliminar(context, nombre: video.titulo);
    if (!confirmado) return;
    try {
      await _authService.eliminarVideoTutorial(video.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = widget.usuario.rol == RolUsuario.administrador;
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Manual de usuario',
      floatingActionButton: esAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.add),
              label: const Text('Agregar video'),
            )
          : null,
      body: StreamBuilder<List<VideoTutorial>>(
        stream: _authService.listarVideosTutoriales(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final videos = snapshot.data ?? [];
          return Column(
            children: [
              Material(
                color: AppColors.superficie,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: AppColors.azulMarino,
                  unselectedLabelColor: AppColors.textoPrincipal,
                  indicatorColor: AppColors.azulMarino,
                  tabs: AudienciaManual.values
                      .map((a) => Tab(text: _tituloManualPara(a)))
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: AudienciaManual.values.map((audiencia) {
                    final videosDeEsteTab = videos
                        .where((v) => v.audiencias.contains(audiencia))
                        .toList();
                    return _ListaVideos(
                      videos: videosDeEsteTab,
                      esAdmin: esAdmin,
                      onEditar: (v) => _abrirFormulario(video: v),
                      onEliminar: _eliminar,
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ListaVideos extends StatelessWidget {
  final List<VideoTutorial> videos;
  final bool esAdmin;
  final void Function(VideoTutorial) onEditar;
  final void Function(VideoTutorial) onEliminar;

  const _ListaVideos({
    required this.videos,
    required this.esAdmin,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Todavía no hay videos para esta sección.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: videos.length,
      itemBuilder: (context, i) {
        final video = videos[i];
        return _TarjetaVideo(
          video: video,
          esAdmin: esAdmin,
          onEditar: () => onEditar(video),
          onEliminar: () => onEliminar(video),
        );
      },
    );
  }
}

/// Cada tarjeta trae su propio `YoutubePlayerController` — necesario
/// para que `YoutubePlayerThumbnail` (miniatura tocable, del paquete
/// `youtube_player_iframe`) solo cargue el reproductor real de ESE video
/// cuando alguien lo toca, no los N videos de la lista de una vez.
class _TarjetaVideo extends StatefulWidget {
  final VideoTutorial video;
  final bool esAdmin;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _TarjetaVideo({
    required this.video,
    required this.esAdmin,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  State<_TarjetaVideo> createState() => _TarjetaVideoState();
}

class _TarjetaVideoState extends State<_TarjetaVideo> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(videoId: widget.video.youtubeId);
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YoutubePlayerThumbnail(controller: _controller),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.video.titulo,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.azulMarino,
                        ),
                      ),
                    ),
                    if (widget.esAdmin) ...[
                      IconButton(
                        onPressed: widget.onEditar,
                        icon: const Icon(Icons.edit, size: 20),
                        tooltip: 'Editar',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: widget.onEliminar,
                        icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.rojo),
                        tooltip: 'Eliminar',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                if (widget.video.descripcion.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(widget.video.descripcion),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formulario de "crear/editar video" (hoja inferior, solo admin). Pide
/// el enlace de YouTube, para quién es, y una descripción opcional — el
/// título NO se pide: se trae solo desde YouTube al guardar.
class _FormularioVideoSheet extends StatefulWidget {
  final VideoTutorial? video;

  const _FormularioVideoSheet({this.video});

  @override
  State<_FormularioVideoSheet> createState() => _FormularioVideoSheetState();
}

class _FormularioVideoSheetState extends State<_FormularioVideoSheet> {
  final _authService = AuthService();
  late final TextEditingController _urlController;
  late final TextEditingController _descripcionController;
  late final Set<AudienciaManual> _audienciasSeleccionadas;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.video?.youtubeUrl ?? '');
    _descripcionController = TextEditingController(text: widget.video?.descripcion ?? '');
    _audienciasSeleccionadas = {...(widget.video?.audiencias ?? [])};
  }

  @override
  void dispose() {
    _urlController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final url = _urlController.text.trim();
    final id = extraerIdYoutube(url);
    if (id == null) {
      setState(
        () => _error =
            'Ese enlace de YouTube no se reconoce. Copia el enlace completo del video.',
      );
      return;
    }
    if (_audienciasSeleccionadas.isEmpty) {
      setState(() => _error = 'Selecciona para quién es este video.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final titulo = await obtenerTituloYoutube(url);
      if (widget.video == null) {
        await _authService.crearVideoTutorial(
          youtubeUrl: url,
          youtubeId: id,
          titulo: titulo,
          descripcion: _descripcionController.text.trim(),
          audiencias: _audienciasSeleccionadas.toList(),
        );
      } else {
        await _authService.editarVideoTutorial(
          id: widget.video!.id,
          youtubeUrl: url,
          youtubeId: id,
          titulo: titulo,
          descripcion: _descripcionController.text.trim(),
          audiencias: _audienciasSeleccionadas.toList(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.video == null ? 'Agregar video' : 'Editar video',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Enlace de YouTube',
                hintText: 'https://www.youtube.com/watch?v=...',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'El título se toma directamente de YouTube — no hace falta escribirlo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descripcionController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '¿Qué muestra este video? (opcional)'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('¿Quién puede verlo?', style: Theme.of(context).textTheme.titleSmall),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: AudienciaManual.values.map((a) {
                final seleccionado = _audienciasSeleccionadas.contains(a);
                return FilterChip(
                  label: Text(_tituloManualPara(a)),
                  selected: seleccionado,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _audienciasSeleccionadas.add(a);
                    } else {
                      _audienciasSeleccionadas.remove(a);
                    }
                  }),
                );
              }).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.rojo)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _cargando ? null : _guardar,
              child: _cargando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.video == null ? 'Agregar' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

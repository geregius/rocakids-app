import 'package:flutter/material.dart';

import '../../models/acudiente.dart';
import '../../models/nino.dart';
import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';
import '../acudiente_detalle_sheet.dart';
import '../nino_detalle_sheet.dart';

/// Niños cuya edad ya no cae en ningún grupo de [gruposEdad] (11 años o
/// más) — mismo criterio que `grupoParaEdad()` devolviendo `null`, y
/// misma etiqueta que ya usan "Menores Registrados"/Dashboard (unificada
/// 2026-08-30, pedido explícito de Rafael tras notar la inconsistencia).
const _mayoresDeOnce = 'Mayores de 11 años';

/// Panel para ver la lista completa de acudientes Y niños (pedido
/// explícito de Rafael, no solo niños) — extiende el pendiente
/// "Administración de Niños" para incluir también a los acudientes.
/// Nació accesible a cualquier rol de servidor (2026-08-14), pero
/// Rafael pidió acotarlo (2026-08-17) a solo administrador, columna y
/// líder de ministerio — ver `RolUsuario.puedeVerAcudientesYNinos` y
/// `puedeVerInfoLiderazgo()` en firestore.rules.
class AdminAcudientesNinosScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const AdminAcudientesNinosScreen({super.key, required this.usuario});

  @override
  State<AdminAcudientesNinosScreen> createState() =>
      _AdminAcudientesNinosScreenState();
}

class _AdminAcudientesNinosScreenState extends State<AdminAcudientesNinosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Acudientes y Niños',
      construirPantalla: () => AdminAcudientesNinosScreen(usuario: widget.usuario),
      body: (context) => Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.azulMarino,
            tabs: const [
              Tab(text: 'Niños'),
              Tab(text: 'Acudientes'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ListaNinos(usuario: widget.usuario),
                _ListaAcudientes(usuario: widget.usuario),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListaNinos extends StatefulWidget {
  final UsuarioApp usuario;
  const _ListaNinos({required this.usuario});

  @override
  State<_ListaNinos> createState() => _ListaNinosState();
}

class _ListaNinosState extends State<_ListaNinos> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';

  // Un controlador por grupo (2026-08-31, pedido de Rafael: los grupos
  // arrancan colapsados — para ver un niño hay que abrir el grupo a
  // mano O buscarlo por nombre, y ahí el grupo con el resultado se
  // despliega solo). `ExpansionTile.initiallyExpanded` solo aplica en
  // el primer build de cada tile — no sirve para forzar que se abra
  // más adelante en reacción a la búsqueda, por eso hace falta un
  // `ExpansibleController` explícito por grupo.
  final _controladores = {
    for (final g in [...gruposEdad, _mayoresDeOnce]) g: ExpansibleController(),
  };

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  // Filtro en memoria sobre la lista que ya trajo el stream completo
  // (2026-08-24, pedido de Rafael: "un botón de buscar") — no dispara
  // ninguna consulta nueva a Firestore, así que no tiene ningún costo
  // adicional de rendimiento ni de lecturas.
  List<Nino> _filtrar(List<Nino> ninos) {
    if (_busqueda.trim().isEmpty) return ninos;
    final q = _busqueda.trim().toLowerCase();
    return ninos
        .where(
          (n) =>
              n.nombreCompleto.toLowerCase().contains(q) ||
              n.identificacionMenor.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _busquedaController,
            decoration: InputDecoration(
              hintText: 'Buscar niño por nombre o documento...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _busquedaController.clear();
                        setState(() => _busqueda = '');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _busqueda = v),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Nino>>(
            stream: AuthService().listarNinosAdmin(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final ninos = _filtrar(snapshot.data ?? []);
              if (ninos.isEmpty) {
                return Center(
                  child: Text(
                    _busqueda.isEmpty
                        ? 'Todavía no hay niños registrados.'
                        : 'No se encontró ningún niño con "$_busqueda".',
                  ),
                );
              }
              // Agrupados por grupo/aula del ministerio (2026-08-30,
              // pedido de Rafael) — mismo criterio que "Menores
              // Registrados" (`grupoParaEdad()` sobre la edad actual),
              // pero acá los grupos son estáticos (no dependen de quién
              // esté presente hoy), así que se recalculan directo sobre
              // TODOS los niños que pasaron el filtro de búsqueda.
              final grupos = <String, List<Nino>>{};
              for (final n in ninos) {
                final grupo = grupoParaEdad(calcularEdad(n.fechaNacimiento)) ?? _mayoresDeOnce;
                grupos.putIfAbsent(grupo, () => []).add(n);
              }
              for (final lista in grupos.values) {
                lista.sort(
                  (a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()),
                );
              }
              final ordenados = [
                ...gruposEdad,
                if (grupos.containsKey(_mayoresDeOnce)) _mayoresDeOnce,
              ];
              // Con una búsqueda activa, el/los grupo(s) que tienen
              // coincidencia se abren solos; sin búsqueda, quedan
              // colapsados (estado por defecto). Se hace después de
              // pintar el frame (`addPostFrameCallback`) porque el
              // controlador de un grupo recién montado todavía no está
              // "adjunto" durante el propio `build()`.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final hayBusqueda = _busqueda.trim().isNotEmpty;
                for (final entrada in _controladores.entries) {
                  if (!grupos.containsKey(entrada.key)) continue;
                  final controlador = entrada.value;
                  if (hayBusqueda && !controlador.isExpanded) {
                    controlador.expand();
                  } else if (!hayBusqueda && controlador.isExpanded) {
                    controlador.collapse();
                  }
                }
              });
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final grupo in ordenados)
                    if (grupos[grupo] != null)
                      _GrupoNinosSection(
                        key: ValueKey(grupo),
                        controller: _controladores[grupo]!,
                        nombre: grupo,
                        ninos: grupos[grupo]!,
                        usuario: widget.usuario,
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Un grupo/aula colapsable dentro de "Niños" — mismo patrón visual que
/// `_GrupoSection` en `ninos_presentes_screen.dart`, pero sin swipe
/// (acá no se registra asistencia, solo se consulta/edita la ficha).
class _GrupoNinosSection extends StatelessWidget {
  final String nombre;
  final List<Nino> ninos;
  final UsuarioApp usuario;
  final ExpansibleController controller;

  const _GrupoNinosSection({
    super.key,
    required this.nombre,
    required this.ninos,
    required this.usuario,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final rangoEdad = rangoEdadPorGrupo[nombre];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: controller,
          // Colapsado por defecto (2026-08-31, pedido de Rafael) — se
          // abre a mano, o solo si hay una búsqueda con coincidencia
          // (ver `_ListaNinosState.build`).
          initiallyExpanded: false,
          title: Text(
            rangoEdad != null
                ? 'Grupo $nombre · $rangoEdad (${ninos.length})'
                // "Mayores de 11 años" ya se lee bien solo — con el
                // prefijo "Grupo" delante quedaría raro.
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
            for (final nino in ninos) _NinoTile(nino: nino, usuario: usuario),
          ],
        ),
      ),
    );
  }
}

class _NinoTile extends StatelessWidget {
  final Nino nino;
  final UsuarioApp usuario;

  const _NinoTile({required this.nino, required this.usuario});

  @override
  Widget build(BuildContext context) {
    final noAutorizaImagen = !nino.autorizoFotoFlag;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.amarillo,
        backgroundImage: nino.fotoUrl.isNotEmpty ? NetworkImage(nino.fotoUrl) : null,
        child: nino.fotoUrl.isEmpty
            ? const Icon(Icons.child_care, color: AppColors.textoPrincipal)
            : null,
      ),
      title: Text(nino.nombreCompleto),
      subtitle: Text(
        '${calcularEdad(nino.fechaNacimiento)} años · '
        '${nino.identificacionMenor.isNotEmpty ? nino.identificacionMenor : 'Sin documento'}',
      ),
      trailing: (!nino.alertaMedicaFlag && !noAutorizaImagen)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (nino.alertaMedicaFlag) ...[
                  const Tooltip(
                    message: 'Tiene condición médica/alergia registrada',
                    child: Icon(Icons.medical_information, color: AppColors.rojo),
                  ),
                  if (noAutorizaImagen) const SizedBox(width: 6),
                ],
                if (noAutorizaImagen)
                  const Tooltip(
                    message: 'NO autoriza uso de imagen — no tomarle fotos ni videos',
                    child: Icon(Icons.no_photography, color: AppColors.rojo),
                  ),
              ],
            ),
      onTap: () => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => NinoDetalleSheet(nino: nino, usuario: usuario),
      ),
    );
  }
}

class _ListaAcudientes extends StatefulWidget {
  final UsuarioApp usuario;
  const _ListaAcudientes({required this.usuario});

  @override
  State<_ListaAcudientes> createState() => _ListaAcudientesState();
}

class _ListaAcudientesState extends State<_ListaAcudientes> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  // Mismo filtro en memoria que `_ListaNinos` — sin consultas nuevas.
  List<Acudiente> _filtrar(List<Acudiente> acudientes) {
    if (_busqueda.trim().isEmpty) return acudientes;
    final q = _busqueda.trim().toLowerCase();
    return acudientes
        .where(
          (a) =>
              a.nombreCompleto.toLowerCase().contains(q) ||
              a.numeroDocumento.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _busquedaController,
            decoration: InputDecoration(
              hintText: 'Buscar acudiente por nombre o documento...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _busquedaController.clear();
                        setState(() => _busqueda = '');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _busqueda = v),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Acudiente>>(
            stream: AuthService().listarAcudientes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final acudientes = _filtrar(snapshot.data ?? []);
              if (acudientes.isEmpty) {
                return Center(
                  child: Text(
                    _busqueda.isEmpty
                        ? 'Todavía no hay acudientes registrados.'
                        : 'No se encontró ningún acudiente con "$_busqueda".',
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: acudientes.length,
                itemBuilder: (context, i) {
                  final acudiente = acudientes[i];
                  final restringido = acudiente.estadoAutorizacion == 'Restringido';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
                      backgroundImage: acudiente.fotoSeguridadUrl.isNotEmpty
                          ? NetworkImage(acudiente.fotoSeguridadUrl)
                          : null,
                      child: acudiente.fotoSeguridadUrl.isEmpty
                          ? const Icon(Icons.person, color: AppColors.textoPrincipal)
                          : null,
                    ),
                    title: Text(acudiente.nombreCompleto),
                    subtitle: Text('${acudiente.tipoDocumento}: ${acudiente.numeroDocumento}'),
                    trailing: restringido
                        ? const Icon(Icons.block, color: AppColors.rojo)
                        : null,
                    onTap: () => showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => AcudienteDetalleSheet(
                        acudiente: acudiente,
                        usuario: widget.usuario,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/acudiente.dart';
import '../../models/nino.dart';
import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';
import '../acudiente_detalle_sheet.dart';
import '../nino_detalle_sheet.dart';

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
      body: Column(
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
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: ninos.length,
                itemBuilder: (context, i) {
                  final nino = ninos[i];
                  final noAutorizaImagen = !nino.autorizoFotoFlag;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.amarillo,
                      backgroundImage: nino.fotoUrl.isNotEmpty
                          ? NetworkImage(nino.fotoUrl)
                          : null,
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
                                  message:
                                      'NO autoriza uso de imagen — no tomarle fotos ni videos',
                                  child: Icon(Icons.no_photography, color: AppColors.rojo),
                                ),
                            ],
                          ),
                    onTap: () => showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => NinoDetalleSheet(nino: nino, usuario: widget.usuario),
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

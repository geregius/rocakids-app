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
/// Accesible por CUALQUIER rol de servidor (no solo admin, ver
/// `AppShell` y `puedeRegistrarAsistencia()` en firestore.rules), para
/// que líderes/columnas/maestros también puedan consultarlo.
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

class _ListaNinos extends StatelessWidget {
  final UsuarioApp usuario;
  const _ListaNinos({required this.usuario});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Nino>>(
      stream: AuthService().listarNinosAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final ninos = snapshot.data ?? [];
        if (ninos.isEmpty) {
          return const Center(child: Text('Todavía no hay niños registrados.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: ninos.length,
          itemBuilder: (context, i) {
            final nino = ninos[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.amarillo,
                backgroundImage:
                    nino.fotoUrl.isNotEmpty ? NetworkImage(nino.fotoUrl) : null,
                child: nino.fotoUrl.isEmpty
                    ? const Icon(Icons.child_care, color: AppColors.textoPrincipal)
                    : null,
              ),
              title: Text(nino.nombreCompleto),
              subtitle: Text(
                '${calcularEdad(nino.fechaNacimiento)} años · '
                '${nino.identificacionMenor.isNotEmpty ? nino.identificacionMenor : 'Sin documento'}',
              ),
              trailing: nino.alertaMedicaFlag
                  ? const Tooltip(
                      message: 'Tiene condición médica/alergia registrada',
                      child: Icon(Icons.medical_information, color: AppColors.rojo),
                    )
                  : null,
              onTap: () => showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => NinoDetalleSheet(nino: nino, usuario: usuario),
              ),
            );
          },
        );
      },
    );
  }
}

class _ListaAcudientes extends StatelessWidget {
  final UsuarioApp usuario;
  const _ListaAcudientes({required this.usuario});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Acudiente>>(
      stream: AuthService().listarAcudientes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final acudientes = snapshot.data ?? [];
        if (acudientes.isEmpty) {
          return const Center(child: Text('Todavía no hay acudientes registrados.'));
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
                builder: (_) =>
                    AcudienteDetalleSheet(acudiente: acudiente, usuario: usuario),
              ),
            );
          },
        );
      },
    );
  }
}

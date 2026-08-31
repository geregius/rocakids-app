import 'package:flutter/material.dart';

import '../models/manual_contenido.dart';
import '../models/usuario_app.dart';
import '../theme/app_colors.dart';
import '../utils/manual_pdf.dart';
import '../widgets/app_shell.dart';

/// "Manual de usuario" (2026-08-20, pedido de Rafael): guía ilustrada de
/// la app, con capturas reales (con nombres/fotos de ejemplo — nunca
/// datos reales de niños o familias), organizada en 3 capítulos según
/// para quién es cada función. Visible para CUALQUIER cuenta con sesión
/// iniciada (acudiente o servidor, cualquier rol) — a diferencia de
/// pantallas como "Dashboard" o "Acudientes y Niños", el manual en sí no
/// expone ningún dato sensible, así que no hay razón para acotarlo por
/// rol. La pestaña inicial se elige según el usuario: un acudiente sin
/// rol de servidor arranca en "Para acudientes"; un servidor arranca en
/// "Para maestros y líderes".
class ManualUsuarioScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const ManualUsuarioScreen({super.key, required this.usuario});

  @override
  State<ManualUsuarioScreen> createState() => _ManualUsuarioScreenState();
}

class _ManualUsuarioScreenState extends State<ManualUsuarioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _generandoPdf = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: manualCapitulos.length,
      vsync: this,
      initialIndex: widget.usuario.rol.esRolDeServidor ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _descargarPdf() async {
    setState(() => _generandoPdf = true);
    try {
      await generarManualPdf();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: widget.usuario,
      seccionActiva: 'Manual de usuario',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generandoPdf ? null : _descargarPdf,
        icon: _generandoPdf
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.picture_as_pdf),
        label: Text(_generandoPdf ? 'Generando…' : 'Descargar PDF'),
      ),
      body: (context) => Column(
        children: [
          Material(
            color: AppColors.superficie,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.azulMarino,
              unselectedLabelColor: AppColors.textoPrincipal,
              indicatorColor: AppColors.azulMarino,
              tabs: manualCapitulos
                  .map((c) => Tab(text: c.titulo))
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: manualCapitulos
                  .map((capitulo) => _CapituloView(capitulo: capitulo))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapituloView extends StatelessWidget {
  final ManualCapitulo capitulo;

  const _CapituloView({required this.capitulo});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          capitulo.descripcion,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.textoPrincipal.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 20),
        for (final seccion in capitulo.secciones) _SeccionCard(seccion: seccion),
      ],
    );
  }
}

class _SeccionCard extends StatelessWidget {
  final ManualSeccion seccion;

  const _SeccionCard({required this.seccion});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            child: AspectRatio(
              aspectRatio: 1280 / 800,
              child: Image.asset(
                'assets/images/manual/${seccion.imagen}',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seccion.titulo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.azulMarino,
                  ),
                ),
                const SizedBox(height: 10),
                for (final punto in seccion.puntos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6, right: 8),
                          child: Icon(Icons.circle, size: 6, color: AppColors.azulClaro),
                        ),
                        Expanded(child: Text(punto)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

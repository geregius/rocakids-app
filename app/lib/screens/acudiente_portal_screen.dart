import 'package:flutter/material.dart';

import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// Portal simple del acudiente: ve a su(s) hijo(s) registrados.
/// Todavía no permite agregar más niños ni editar datos — eso llega
/// en una siguiente vuelta del Módulo 3.
class AcudientePortalScreen extends StatefulWidget {
  final UsuarioApp usuario;

  const AcudientePortalScreen({super.key, required this.usuario});

  @override
  State<AcudientePortalScreen> createState() => _AcudientePortalScreenState();
}

class _AcudientePortalScreenState extends State<AcudientePortalScreen> {
  late Future<List<Nino>> _hijosFuture;

  @override
  void initState() {
    super.initState();
    _hijosFuture = AuthService().obtenerMisHijos();
  }

  int _calcularEdad(DateTime fechaNacimiento) {
    final ahora = DateTime.now();
    var edad = ahora.year - fechaNacimiento.year;
    if (ahora.month < fechaNacimiento.month ||
        (ahora.month == fechaNacimiento.month && ahora.day < fechaNacimiento.day)) {
      edad--;
    }
    return edad;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RocaKids'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Bienvenido, ${widget.usuario.nombre}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Nino>>(
              future: _hijosFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final hijos = snapshot.data ?? [];
                if (hijos.isEmpty) {
                  return const Center(child: Text('Todavía no tienes niños registrados.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: hijos.length,
                  itemBuilder: (context, i) {
                    final nino = hijos[i];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.amarillo,
                          child: Icon(Icons.child_care, color: AppColors.textoPrincipal),
                        ),
                        title: Text(nino.nombreCompleto),
                        subtitle: Text('${_calcularEdad(nino.fechaNacimiento)} años · ${nino.genero}'),
                        trailing: nino.alertaMedicaFlag
                            ? const Tooltip(
                                message: 'Tiene condición médica/alergia registrada',
                                child: Icon(Icons.medical_information, color: AppColors.rojo),
                              )
                            : null,
                      ),
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

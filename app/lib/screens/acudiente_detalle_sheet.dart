import 'package:flutter/material.dart';

import '../models/acudiente.dart';
import '../models/nino.dart';
import '../models/usuario_app.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'editar_acudiente_sheet.dart';

/// Hoja inferior con la ficha completa de un acudiente: documento,
/// contacto, foto de seguridad y los niños que tiene vinculados. Quien
/// hace check-in/out (misma lista de roles que [RolUsuario.esRolDeServidor],
/// ver firestore.rules `puedeRegistrarAsistencia()`) o un admin pueden
/// editar la información desde acá — decisión de Rafael, "para facilitar
/// el proceso".
class AcudienteDetalleSheet extends StatefulWidget {
  final Acudiente acudiente;
  final UsuarioApp usuario;

  const AcudienteDetalleSheet({
    super.key,
    required this.acudiente,
    required this.usuario,
  });

  @override
  State<AcudienteDetalleSheet> createState() => _AcudienteDetalleSheetState();
}

class _AcudienteDetalleSheetState extends State<AcudienteDetalleSheet> {
  late Acudiente _acudiente;
  bool _cargandoHijos = true;
  List<Nino> _hijos = [];

  bool get _puedeEditar => widget.usuario.rol.esRolDeServidor;

  @override
  void initState() {
    super.initState();
    _acudiente = widget.acudiente;
    _cargarHijos();
  }

  Future<void> _cargarHijos() async {
    try {
      final hijos = await AuthService().obtenerHijosDeAcudiente(_acudiente.uid);
      if (mounted) {
        setState(() {
          _hijos = hijos;
          _cargandoHijos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoHijos = false);
    }
  }

  Future<void> _abrirEdicion() async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditarAcudienteSheet(acudiente: _acudiente),
    );
    if (guardado == true && mounted) Navigator.of(context).pop(true);
  }

  /// Aviso de que este acudiente no tiene correo (o llegó duplicado con
  /// otro al migrar los datos históricos, 2026-08-18) — sin esto no
  /// puede iniciar sesión con su propia cuenta. Desaparece solo en
  /// cuanto alguien le guarde un correo real desde "Editar información".
  Widget _avisoCorreoPendiente() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amarillo.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.textoPrincipal),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Falta el correo real de este acudiente (o coincidía con el '
              'de otro al migrar los datos). Pídeselo a la familia y '
              'actualízalo con "Editar información".',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _acudiente;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.azulClaro.withValues(alpha: 0.2),
                  backgroundImage: a.fotoSeguridadUrl.isNotEmpty
                      ? NetworkImage(a.fotoSeguridadUrl)
                      : null,
                  child: a.fotoSeguridadUrl.isEmpty
                      ? const Icon(Icons.person, color: AppColors.textoPrincipal)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.nombreCompleto, style: Theme.of(context).textTheme.titleLarge),
                      if (a.estadoAutorizacion == 'Restringido')
                        Text(
                          a.observacionesRestriccion.isNotEmpty
                              ? 'RESTRINGIDO: ${a.observacionesRestriccion}'
                              : 'RESTRINGIDO',
                          style: const TextStyle(
                            color: AppColors.rojo,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FilaDato('Documento', '${a.tipoDocumento}: ${a.numeroDocumento}'),
            _FilaDato('Teléfono', a.telefonoCelular),
            _FilaDato('Correo', a.correoElectronico.isNotEmpty ? a.correoElectronico : 'Sin correo'),
            if (a.correoPendienteDeCorregir) ...[
              const SizedBox(height: 8),
              _avisoCorreoPendiente(),
            ],
            const SizedBox(height: 16),
            Text('Niños vinculados', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            if (_cargandoHijos)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_hijos.isEmpty)
              const Text('No tiene niños vinculados todavía.')
            else
              ..._hijos.map(
                (n) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.amarillo,
                    backgroundImage:
                        n.fotoUrl.isNotEmpty ? NetworkImage(n.fotoUrl) : null,
                    child: n.fotoUrl.isEmpty
                        ? const Icon(Icons.child_care, color: AppColors.textoPrincipal)
                        : null,
                  ),
                  title: Text(n.nombreCompleto),
                  subtitle: Text('${calcularEdad(n.fechaNacimiento)} años'),
                ),
              ),
            if (_puedeEditar) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _abrirEdicion,
                icon: const Icon(Icons.edit),
                label: const Text('Editar información'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _FilaDato(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}

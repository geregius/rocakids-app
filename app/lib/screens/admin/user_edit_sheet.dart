import 'package:flutter/material.dart';

import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';

/// Hoja inferior para que un admin asigne rol y estado a un usuario.
class UserEditSheet extends StatefulWidget {
  final UsuarioApp usuario;

  const UserEditSheet({super.key, required this.usuario});

  @override
  State<UserEditSheet> createState() => _UserEditSheetState();
}

class _UserEditSheetState extends State<UserEditSheet> {
  late RolUsuario _rolSeleccionado;
  late bool _activo;
  DateTime? _fechaVerificacionAntecedentes;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _rolSeleccionado = widget.usuario.rol == RolUsuario.desconocido
        ? RolUsuario.usuarioExterno
        : widget.usuario.rol;
    _activo = widget.usuario.activo;
    _fechaVerificacionAntecedentes = widget.usuario.fechaVerificacionAntecedentes;
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaVerificacionAntecedentes ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (fecha != null) setState(() => _fechaVerificacionAntecedentes = fecha);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await AuthService().actualizarRolYEstado(
        uid: widget.usuario.uid,
        rol: _rolSeleccionado,
        activo: _activo,
        fechaVerificacionAntecedentes: _fechaVerificacionAntecedentes,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;

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
                  backgroundImage: u.fotoUrl.isNotEmpty ? NetworkImage(u.fotoUrl) : null,
                  child: u.fotoUrl.isEmpty ? Text(u.nombre.isNotEmpty ? u.nombre[0] : '?') : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.nombreCompleto.isNotEmpty ? u.nombreCompleto : u.correo,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(u.correo, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (u.perfilCompleto) ...[
              const SizedBox(height: 16),
              _FilaDato('Documento', '${u.tipoDocumento} ${u.numeroDocumento}'),
              _FilaDato('Teléfono', u.telefono),
              _FilaDato('EPS', u.epsNombre),
              _FilaDato('Grupo sanguíneo', u.grupoSanguineo),
              _FilaDato('Contacto de emergencia', '${u.contactoEmergenciaNombre} · ${u.contactoEmergenciaTelefono}'),
            ] else ...[
              const SizedBox(height: 12),
              const Text(
                'Este usuario todavía no ha completado su perfil de servidor.',
                style: TextStyle(color: AppColors.rojo),
              ),
            ],
            const SizedBox(height: 20),
            DropdownButtonFormField<RolUsuario>(
              initialValue: _rolSeleccionado,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: RolUsuario.asignables
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.etiqueta)))
                  .toList(),
              onChanged: (r) => setState(() => _rolSeleccionado = r!),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cuenta activa'),
              subtitle: const Text('Si la desactivas, la persona no podrá iniciar sesión'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Verificación de antecedentes'),
              subtitle: Text(
                _fechaVerificacionAntecedentes != null
                    ? _formatearFecha(_fechaVerificacionAntecedentes!)
                    : 'Sin registrar',
              ),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _elegirFecha,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatearFecha(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

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
            width: 140,
            child: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}

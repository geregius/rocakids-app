import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/usuario_app.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/llamar_telefono.dart';
import '../../widgets/confirmar_eliminar.dart';
import 'edit_perfil_servidor_sheet.dart';

/// Hoja inferior con la ficha de un usuario. Quién la abre determina qué
/// ve: un admin ve y puede cambiar rol/estado/antecedentes de cualquiera;
/// cualquier usuario viendo su propia ficha (o un admin viendo la suya)
/// puede editar su información de perfil.
class UserEditSheet extends StatefulWidget {
  final UsuarioApp usuario;
  final bool esAdmin;

  const UserEditSheet({super.key, required this.usuario, required this.esAdmin});

  @override
  State<UserEditSheet> createState() => _UserEditSheetState();
}

class _UserEditSheetState extends State<UserEditSheet> {
  late RolUsuario _rolSeleccionado;
  late bool _activo;
  DateTime? _fechaVerificacionAntecedentes;
  bool _guardando = false;
  bool _eliminando = false;

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

  bool get _esPropio => FirebaseAuth.instance.currentUser?.uid == widget.usuario.uid;
  bool get _puedeEditarPerfil => widget.esAdmin || _esPropio;

  Future<void> _eliminar() async {
    final confirmado = await confirmarEliminar(
      context,
      nombre: widget.usuario.nombreCompleto.isNotEmpty
          ? widget.usuario.nombreCompleto
          : widget.usuario.correo,
    );
    if (!confirmado) return;
    setState(() => _eliminando = true);
    try {
      await AuthService().eliminarServidor(widget.usuario.uid);
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

  Future<void> _abrirEdicionPerfil() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditPerfilServidorSheet(usuario: widget.usuario, esPropio: _esPropio),
    );
    // Cerramos también esta ficha: sus datos quedaron desactualizados y el
    // usuario puede volver a abrirla para ver la información ya al día.
    if (mounted) Navigator.of(context).pop();
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
            const SizedBox(height: 16),
            _FilaDato(
              'Fecha de nacimiento',
              u.fechaNacimiento != null
                  ? _formatearFecha(u.fechaNacimiento!)
                  : 'Sin registrar',
            ),
            if (u.perfilCompleto) ...[
              _FilaDato('Correo electrónico', u.correo),
              _FilaDato('Documento', '${u.tipoDocumento} ${u.numeroDocumento}'),
              _FilaDato('Teléfono', u.telefono),
              _FilaDato('EPS', u.epsNombre),
              _FilaDato('Grupo sanguíneo', u.grupoSanguineo),
              _FilaDato(
                'Contacto de emergencia',
                '${u.contactoEmergenciaNombre} · ${u.contactoEmergenciaTelefono}',
                trailing: u.contactoEmergenciaTelefono.isNotEmpty
                    ? IconButton(
                        onPressed: () => llamarTelefono(context, u.contactoEmergenciaTelefono),
                        icon: const Icon(Icons.call, color: AppColors.azulMarino),
                        tooltip: 'Llamar a ${u.contactoEmergenciaTelefono}',
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text(
                'Este usuario todavía no ha completado su perfil de servidor.',
                style: TextStyle(color: AppColors.rojo),
              ),
            ],
            if (_puedeEditarPerfil) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _abrirEdicionPerfil,
                icon: const Icon(Icons.edit),
                label: const Text('Editar información'),
              ),
            ],
            if (widget.esAdmin) ...[
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
              if (!_esPropio) ...[
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
                  label: const Text('Eliminar servidor'),
                ),
              ],
            ],
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
  final Widget? trailing;
  const _FilaDato(this.etiqueta, this.valor, {this.trailing});

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
          ?trailing,
        ],
      ),
    );
  }
}

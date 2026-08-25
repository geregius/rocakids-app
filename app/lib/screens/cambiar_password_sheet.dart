import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// Formulario para que CUALQUIER usuario logueado (servidor o acudiente)
/// cambie su propia contraseña — accesible desde el menú de `AppShell`
/// para todos los perfiles, no solo servidores. Pide la contraseña
/// actual porque Firebase Auth exige reautenticación reciente para esta
/// operación (ver [AuthService.cambiarPassword]).
class CambiarPasswordSheet extends StatefulWidget {
  const CambiarPasswordSheet({super.key});

  @override
  State<CambiarPasswordSheet> createState() => _CambiarPasswordSheetState();
}

class _CambiarPasswordSheetState extends State<CambiarPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _actualController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();
  bool _mostrarPassword = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await AuthService().cambiarPassword(
        passwordActual: _actualController.text,
        passwordNueva: _nuevaController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.mensaje;
          _guardando = false;
        });
      }
    } catch (e) {
      // Antes solo se atrapaba `AuthException` — cualquier otro error
      // dejaba `_guardando` en `true` para siempre, sin mensaje y sin
      // que el botón volviera a responder (2026-08-25, mismo bug
      // corregido en "Registrar familia"/"Registro de Acudiente",
      // aplicado también acá).
      if (mounted) {
        setState(() {
          _error = 'No se pudo cambiar la contraseña: $e';
          _guardando = false;
        });
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
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cambiar contraseña', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _actualController,
                obscureText: !_mostrarPassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña actual',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _mostrarPassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.azulMarino,
                    ),
                    tooltip: _mostrarPassword ? 'Ocultar contraseñas' : 'Mostrar contraseñas',
                    onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu contraseña actual' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nuevaController,
                obscureText: !_mostrarPassword,
                decoration: const InputDecoration(labelText: 'Contraseña nueva'),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa la contraseña nueva';
                  if (v.length < 6) return 'Mínimo 6 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmarController,
                obscureText: !_mostrarPassword,
                decoration: const InputDecoration(labelText: 'Confirmar contraseña nueva'),
                validator: (v) =>
                    v != _nuevaController.text ? 'Las contraseñas no coinciden' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.rojo),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar contraseña'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

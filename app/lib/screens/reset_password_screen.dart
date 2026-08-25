import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';

/// Pantalla propia para completar el restablecimiento de contraseña,
/// abierta directamente por el enlace del correo de recuperación (ver
/// `enviarCorreoRecuperacion` en `functions/index.js` — el enlace usa
/// `handleCodeInApp: true`, así que llega aquí en vez de a la página
/// genérica de Firebase). `main.dart` decide mostrar esta pantalla
/// leyendo `?mode=resetPassword&oobCode=...` de la URL.
class ResetPasswordScreen extends StatefulWidget {
  final String oobCode;

  const ResetPasswordScreen({super.key, required this.oobCode});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _authService = AuthService();

  bool _mostrarPassword = false;
  bool _verificando = true;
  bool _guardando = false;
  bool _completado = false;
  String? _correo;
  String? _errorVerificacion;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verificarCodigo();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _verificarCodigo() async {
    try {
      final correo = await _authService.verificarCodigoRecuperacion(widget.oobCode);
      if (!mounted) return;
      setState(() {
        _correo = correo;
        _verificando = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorVerificacion = e.mensaje;
        _verificando = false;
      });
    } catch (e) {
      // Antes solo se atrapaba `AuthException` — cualquier otro error
      // (de red, por ejemplo) dejaba `_verificando` en `true` para
      // siempre: la pantalla se quedaba en el spinner inicial sin
      // ninguna forma de reintentar (2026-08-25, mismo bug corregido
      // en "Registrar familia"/"Registro de Acudiente").
      if (!mounted) return;
      setState(() {
        _errorVerificacion = 'No se pudo verificar el enlace: $e';
        _verificando = false;
      });
    }
  }

  Future<void> _guardarNuevaPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await _authService.confirmarNuevaPassword(
        oobCode: widget.oobCode,
        nuevaPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _completado = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar la nueva contraseña: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _irAlLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/logo_rocakids.png', height: 140),
                  const SizedBox(height: 32),
                  if (_verificando) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Verificando enlace...'),
                  ] else if (_errorVerificacion != null) ...[
                    const Icon(Icons.error_outline, color: AppColors.rojo, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _errorVerificacion!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.rojo),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _irAlLogin,
                        child: const Text('Volver al inicio de sesión'),
                      ),
                    ),
                  ] else if (_completado) ...[
                    const Icon(Icons.check_circle, color: AppColors.azulMarino, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Contraseña actualizada',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: AppColors.textoPrincipal),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ya puedes iniciar sesión con tu nueva contraseña.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _irAlLogin,
                        child: const Text('Ir a iniciar sesión'),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Elige tu nueva contraseña',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: AppColors.textoPrincipal),
                      textAlign: TextAlign.center,
                    ),
                    if (_correo != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _correo!,
                        style: TextStyle(color: Colors.grey[700]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_mostrarPassword,
                            decoration: InputDecoration(
                              labelText: 'Nueva contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _mostrarPassword ? Icons.visibility_off : Icons.visibility,
                                  color: AppColors.azulMarino,
                                ),
                                onPressed: () =>
                                    setState(() => _mostrarPassword = !_mostrarPassword),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Ingresa tu nueva contraseña';
                              }
                              if (value.length < 6) {
                                return 'Mínimo 6 caracteres';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmarController,
                            obscureText: !_mostrarPassword,
                            decoration: const InputDecoration(
                              labelText: 'Confirmar contraseña',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            validator: (value) {
                              if (value != _passwordController.text) {
                                return 'Las contraseñas no coinciden';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _guardarNuevaPassword(),
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
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _guardando ? null : _guardarNuevaPassword,
                              child: _guardando
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Cambiar contraseña'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

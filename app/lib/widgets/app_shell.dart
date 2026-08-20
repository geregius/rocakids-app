import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../screens/acudiente_portal_screen.dart';
import '../screens/admin/admin_acudientes_ninos_screen.dart';
import '../screens/admin/admin_users_list_screen.dart';
import '../screens/admin/dashboard_screen.dart';
import '../screens/admin/user_edit_sheet.dart';
import '../screens/auth_gate.dart';
import '../screens/cambiar_password_sheet.dart';
import '../screens/cumpleanos_ninos_screen.dart';
import '../screens/cumpleanos_servidores_screen.dart';
import '../screens/home_screen.dart';
import '../screens/modo_emergencia_screen.dart';
import '../screens/modulo_en_construccion_screen.dart';
import '../screens/ninos_presentes_screen.dart';
import '../screens/registrar_familia_screen.dart';
import '../screens/registro_asistencia_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// Ancho de pantalla a partir del cual el menú queda siempre visible a
/// la izquierda, en vez de colapsar en un cajón deslizable (celular).
const _anchoMenuFijo = 800.0;

/// Estructura común de todas las pantallas principales: un menú con
/// todas las secciones (fijo a la izquierda en pantallas anchas, cajón
/// deslizable en celular) y el contenido de la sección activa a la
/// derecha. Qué aparece en el menú depende del rol de [usuario]. Cada
/// pantalla se envuelve en este shell y le pasa su propio contenido
/// como [body], más el nombre de su sección en [seccionActiva] (para
/// que quede resaltada en el menú y como título de la barra superior).
class AppShell extends StatelessWidget {
  final UsuarioApp usuario;
  final String seccionActiva;
  final Widget body;
  final Widget? floatingActionButton;

  const AppShell({
    super.key,
    required this.usuario,
    required this.seccionActiva,
    required this.body,
    this.floatingActionButton,
  });

  void _irA(BuildContext context, Widget pantalla) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => pantalla));
  }

  /// Cierra la sesión y SIEMPRE cae en la pantalla de login, sin importar
  /// desde qué sección se haya tocado "Cerrar sesión". Necesario porque
  /// `_irA()` navega con `pushReplacement`: la primera vez que se cambia
  /// de sección desde el menú, la ruta de `AuthGate` (el widget que
  /// decide qué pantalla mostrar según el estado de sesión) queda
  /// reemplazada y sale del árbol de navegación — así que ya no hay
  /// nadie escuchando `authStateChanges` para reaccionar solo al cerrar
  /// sesión. Por eso, en vez de confiar en esa reactividad, se limpia
  /// TODO el stack de navegación y se vuelve a poner `AuthGate` desde
  /// cero, que con la sesión ya cerrada muestra el login de inmediato.
  Future<void> _cerrarSesion(BuildContext context) async {
    await AuthService().signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  List<_ItemMenu> _items(BuildContext context) {
    final esAdmin = usuario.rol == RolUsuario.administrador;
    final esServidor = usuario.rol.esRolDeServidor;

    return [
      if (esServidor)
        _ItemMenu(
          icon: Icons.home,
          label: 'Inicio',
          onTap: () => _irA(
            context,
            esAdmin
                ? HomeScreen(usuario: usuario)
                : ModuloEnConstruccionScreen(usuario: usuario),
          ),
        ),
      _ItemMenu(
        icon: Icons.family_restroom,
        label: 'Mis hijos',
        onTap: () => _irA(context, AcudientePortalScreen(usuario: usuario)),
      ),
      if (esServidor)
        _ItemMenu(
          icon: Icons.assignment_turned_in,
          label: 'Registro de asistencia',
          onTap: () =>
              _irA(context, RegistroAsistenciaScreen(usuario: usuario)),
        ),
      if (esServidor)
        _ItemMenu(
          icon: Icons.fact_check,
          label: 'Menores Recibidos',
          onTap: () => _irA(context, NinosPresentesScreen(usuario: usuario)),
        ),
      if (esServidor)
        _ItemMenu(
          icon: Icons.group_add,
          label: 'Registrar familia',
          onTap: () => _irA(context, RegistrarFamiliaScreen(usuario: usuario)),
        ),
      if (esServidor)
        _ItemMenu(
          icon: Icons.cake,
          label: 'Cumpleaños niños',
          onTap: () => _irA(context, CumpleanosNinosScreen(usuario: usuario)),
        ),
      // Solo administrador, columna y líder de ministerio (2026-08-19,
      // mismo criterio que "Acudientes y Niños"/"Dashboard") — a
      // diferencia de "Cumpleaños niños", `usuarios` guarda datos
      // sensibles del servidor ya acotados a liderazgo en el resto de
      // la app.
      if (usuario.rol.puedeVerAcudientesYNinos)
        _ItemMenu(
          icon: Icons.celebration,
          label: 'Cumpleaños Servidores',
          onTap: () =>
              _irA(context, CumpleanosServidoresScreen(usuario: usuario)),
        ),
      // Mismo criterio que "Acudientes y Niños": solo administrador,
      // columna y líder de ministerio (2026-08-18, pedido de Rafael).
      if (usuario.rol.puedeVerDashboard)
        _ItemMenu(
          icon: Icons.bar_chart,
          label: 'Dashboard',
          onTap: () => _irA(context, DashboardScreen(usuario: usuario)),
        ),
      // Solo administrador, columna y líder de ministerio (2026-08-17,
      // pedido explícito de Rafael) — NO todos los roles principales.
      if (usuario.rol.puedeVerAcudientesYNinos)
        _ItemMenu(
          icon: Icons.diversity_3,
          label: 'Acudientes y Niños',
          onTap: () =>
              _irA(context, AdminAcudientesNinosScreen(usuario: usuario)),
        ),
      if (esAdmin)
        _ItemMenu(
          icon: Icons.people,
          label: 'Gestión de Servidores',
          onTap: () => _irA(context, AdminUsersListScreen(usuario: usuario)),
        ),
      // Solo administrador, columna y líder de ministerio pueden
      // activar/desactivar el modo (2026-08-19, pedido explícito de
      // Rafael) — mientras está inactivo, este ítem es la única forma
      // de llegar a la pantalla (navegación normal, con el menú de
      // siempre). Una vez activo, TODA la app reacciona sola sin
      // depender de este ítem — ver la rama de bloqueo en `build()`.
      if (usuario.rol.puedeActivarModoEmergencia)
        _ItemMenu(
          icon: Icons.priority_high,
          label: 'Modo emergencia',
          onTap: () => _irA(context, _EmergenciaScreenWrapper(usuario: usuario)),
        ),
      if (esServidor)
        _ItemMenu(
          icon: Icons.person,
          label: 'Mi perfil',
          separadorAntes: true,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => UserEditSheet(usuario: usuario, esAdmin: esAdmin),
          ),
        ),
      // Cualquier usuario logueado (servidor o acudiente) puede cambiar
      // su propia contraseña — pedido de Rafael, disponible en todos los
      // perfiles, no solo el de servidor.
      _ItemMenu(
        icon: Icons.lock,
        label: 'Cambiar contraseña',
        separadorAntes: !esServidor,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const CambiarPasswordSheet(),
        ),
      ),
      _ItemMenu(
        icon: Icons.logout,
        label: 'Cerrar sesión',
        onTap: () => _cerrarSesion(context),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // "Modo emergencia" (2026-08-19, pedido de Rafael): estado GLOBAL,
    // reactivo para toda la app — mientras está activo, un
    // administrador sigue viendo todo normal (no pasa por esta rama);
    // cualquier otro servidor queda restringido SOLO a la pantalla de
    // emergencia (sin el menú de siempre); un acudiente sin rol de
    // servidor ve un aviso de bloqueo. Se resuelve acá, en el único
    // widget que envuelve TODAS las pantallas autenticadas, para que
    // ninguna pantalla existente tenga que acordarse de revisar esto
    // por su cuenta.
    return StreamBuilder<bool>(
      stream: AuthService().emergenciaActivaStream(),
      builder: (context, snapshot) {
        final emergenciaActiva = snapshot.data ?? false;
        final esAdmin = usuario.rol == RolUsuario.administrador;

        if (emergenciaActiva && !esAdmin) {
          if (usuario.rol.esRolDeServidor) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Modo emergencia'),
                backgroundColor: AppColors.rojo,
                foregroundColor: Colors.white,
                actions: [
                  IconButton(
                    onPressed: () => _cerrarSesion(context),
                    icon: const Icon(Icons.logout),
                    tooltip: 'Cerrar sesión',
                  ),
                ],
              ),
              body: ModoEmergenciaBody(usuario: usuario),
            );
          }
          return _BloqueoEmergenciaAcudiente(onCerrarSesion: () => _cerrarSesion(context));
        }

        // El admin no queda restringido por el modo emergencia (sigue
        // navegando toda la app normal), pero necesita una señal visual
        // clara en CUALQUIER pantalla de que sigue activo — pedido de
        // Rafael, 2026-08-19: un borde con degradado rojo alrededor de
        // toda la pantalla. `IgnorePointer` para que no bloquee ningún
        // toque debajo.
        if (emergenciaActiva && esAdmin) {
          return Stack(
            children: [
              _buildNormal(context),
              const Positioned.fill(
                child: IgnorePointer(child: _BordeEmergenciaAdmin()),
              ),
            ],
          );
        }

        return _buildNormal(context);
      },
    );
  }

  Widget _buildNormal(BuildContext context) {
    final items = _items(context);
    final esAncho = MediaQuery.of(context).size.width >= _anchoMenuFijo;

    if (esAncho) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Menu(
              usuario: usuario,
              items: items,
              seccionActiva: seccionActiva,
              dentroDeDrawer: false,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Scaffold(
                appBar: AppBar(title: Text(seccionActiva)),
                body: body,
                floatingActionButton: floatingActionButton,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(seccionActiva)),
      drawer: Drawer(
        child: _Menu(
          usuario: usuario,
          items: items,
          seccionActiva: seccionActiva,
          dentroDeDrawer: true,
        ),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Envuelve `ModoEmergenciaBody` en un `AppShell` normal, con el menú de
/// siempre — es como llega leadership a la pantalla desde el ítem de
/// menú CUANDO la emergencia todavía no está activa (para poder
/// activarla). Una vez activa, `AppShell.build()` ya no usa este
/// wrapper: reemplaza TODO por `ModoEmergenciaBody` directamente, sin
/// menú, para cualquier servidor (ver arriba).
class _EmergenciaScreenWrapper extends StatelessWidget {
  final UsuarioApp usuario;
  const _EmergenciaScreenWrapper({required this.usuario});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      usuario: usuario,
      seccionActiva: 'Modo emergencia',
      body: ModoEmergenciaBody(usuario: usuario),
    );
  }
}

/// Borde con degradado rojo en los 4 costados de la pantalla — visible
/// SOLO para el administrador mientras "Modo emergencia" está activo
/// (pedido de Rafael, 2026-08-19). A diferencia de cualquier otro
/// servidor, un admin no queda restringido a la pantalla de emergencia,
/// así que esta es su única señal de que el modo sigue encendido sin
/// importar en qué pantalla esté. Se dibuja con 4 franjas en degradado
/// (`LinearGradient`, rojo → transparente) en vez de un `Border` normal
/// porque `BoxDecoration.border` no admite degradados.
class _BordeEmergenciaAdmin extends StatelessWidget {
  const _BordeEmergenciaAdmin();

  static const _grosor = 18.0;

  Widget _franja({required Alignment desde, required Alignment hacia}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: desde,
          end: hacia,
          colors: [
            AppColors.rojo.withValues(alpha: 0.85),
            AppColors.rojo.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _grosor,
          child: _franja(desde: Alignment.topCenter, hacia: Alignment.bottomCenter),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: _grosor,
          child: _franja(desde: Alignment.bottomCenter, hacia: Alignment.topCenter),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: _grosor,
          child: _franja(desde: Alignment.centerLeft, hacia: Alignment.centerRight),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: _grosor,
          child: _franja(desde: Alignment.centerRight, hacia: Alignment.centerLeft),
        ),
      ],
    );
  }
}

/// Lo que ve un acudiente (sin rol de servidor) mientras el modo
/// emergencia está activo — pierde acceso a "Mis hijos" y cualquier
/// otra pantalla hasta que un admin/columna/líder de ministerio lo
/// desactive.
class _BloqueoEmergenciaAcudiente extends StatelessWidget {
  final VoidCallback onCerrarSesion;
  const _BloqueoEmergenciaAcudiente({required this.onCerrarSesion});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RocaKids'),
        backgroundColor: AppColors.rojo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: onCerrarSesion,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.priority_high, color: AppColors.rojo, size: 56),
              const SizedBox(height: 16),
              Text(
                'La app está en modo emergencia',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Por seguridad, el acceso a "Mis hijos" está temporalmente '
                'suspendido. Acércate a un líder de ministerio, columna o '
                'administrador para más información.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemMenu {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool separadorAntes;

  const _ItemMenu({
    required this.icon,
    required this.label,
    required this.onTap,
    this.separadorAntes = false,
  });
}

class _Menu extends StatelessWidget {
  final UsuarioApp usuario;
  final List<_ItemMenu> items;
  final String seccionActiva;
  final bool dentroDeDrawer;

  const _Menu({
    required this.usuario,
    required this.items,
    required this.seccionActiva,
    required this.dentroDeDrawer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: AppColors.superficie,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RocaKids',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.azulMarino,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    usuario.nombreCompleto.isNotEmpty
                        ? usuario.nombreCompleto
                        : usuario.correo,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    usuario.rol.etiqueta,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final item in items) ...[
                    if (item.separadorAntes) const Divider(height: 16),
                    ListTile(
                      leading: Icon(
                        item.icon,
                        color: item.label == seccionActiva
                            ? AppColors.azulMarino
                            : AppColors.textoPrincipal,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          color: item.label == seccionActiva
                              ? AppColors.azulMarino
                              : AppColors.textoPrincipal,
                          fontWeight: item.label == seccionActiva
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      selected: item.label == seccionActiva,
                      selectedTileColor: AppColors.azulClaro.withValues(
                        alpha: 0.1,
                      ),
                      onTap: () {
                        if (dentroDeDrawer) Navigator.of(context).pop();
                        item.onTap();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

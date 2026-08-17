import 'package:flutter/material.dart';

import '../models/usuario_app.dart';
import '../screens/acudiente_portal_screen.dart';
import '../screens/admin/admin_acudientes_ninos_screen.dart';
import '../screens/admin/admin_users_list_screen.dart';
import '../screens/admin/user_edit_sheet.dart';
import '../screens/auth_gate.dart';
import '../screens/home_screen.dart';
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

  Future<void> _reindexar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Reindexando...')));
    try {
      final total = await AuthService().reindexarBusquedaNinos();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$total niños reindexados para la búsqueda por nombre.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo reindexar: $e')),
      );
    }
  }

  Future<void> _migrarRelaciones(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Migrando vínculos...')),
    );
    try {
      final total = await AuthService().migrarRelacionesADeterministico();
      messenger.showSnackBar(
        SnackBar(content: Text('$total vínculos niño-acudiente migrados.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo migrar: $e')));
    }
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

  Future<void> _sincronizarPresencia(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Sincronizando presencia...')),
    );
    try {
      final total = await AuthService().sincronizarPresenciaNinos();
      messenger.showSnackBar(
        SnackBar(content: Text('$total niños marcados como presentes hoy.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo sincronizar: $e')),
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
      // Solo administrador, columna y líder de ministerio (2026-08-17,
      // pedido explícito de Rafael) — NO todos los roles principales.
      if (usuario.rol.puedeVerAcudientesYNinos)
        _ItemMenu(
          icon: Icons.diversity_3,
          label: 'Acudientes y Niños',
          onTap: () =>
              _irA(context, AdminAcudientesNinosScreen(usuario: usuario)),
        ),
      if (esAdmin) ...[
        _ItemMenu(
          icon: Icons.people,
          label: 'Gestión de Servidores',
          onTap: () => _irA(context, AdminUsersListScreen(usuario: usuario)),
        ),
        _ItemMenu(
          icon: Icons.sync,
          label: 'Reindexar búsqueda de niños',
          onTap: () => _reindexar(context),
        ),
        _ItemMenu(
          icon: Icons.link,
          label: 'Migrar vínculos niño-acudiente',
          onTap: () => _migrarRelaciones(context),
        ),
        _ItemMenu(
          icon: Icons.checklist,
          label: 'Sincronizar presencia de niños',
          onTap: () => _sincronizarPresencia(context),
        ),
      ],
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
      _ItemMenu(
        icon: Icons.logout,
        label: 'Cerrar sesión',
        separadorAntes: !esServidor,
        onTap: () => _cerrarSesion(context),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
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

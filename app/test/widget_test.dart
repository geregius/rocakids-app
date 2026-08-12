// Pruebas del modelo de rol de usuario.
//
// Nota: las pantallas (LoginScreen, AuthGate, etc.) dependen de Firebase,
// que no está inicializado en el entorno de test. Probarlas requiere mocks
// de Firebase (ej. firebase_auth_mocks / fake_cloud_firestore) — se agregan
// cuando el módulo de autenticación tenga más lógica que valga la pena cubrir.

import 'package:flutter_test/flutter_test.dart';
import 'package:rocakids/models/usuario_app.dart';

void main() {
  group('RolUsuario.fromString', () {
    test('reconoce "administrador"', () {
      expect(RolUsuario.fromString('administrador'), RolUsuario.administrador);
    });

    test('es insensible a mayúsculas/minúsculas y espacios', () {
      expect(RolUsuario.fromString('Administrador'), RolUsuario.administrador);
      expect(RolUsuario.fromString('  ADMINISTRADOR '), RolUsuario.administrador);
    });

    test('valores nulos o desconocidos caen en RolUsuario.desconocido', () {
      expect(RolUsuario.fromString(null), RolUsuario.desconocido);
      expect(RolUsuario.fromString('lo-que-sea'), RolUsuario.desconocido);
    });
  });

  group('UsuarioApp.fromFirestore', () {
    test('mapea los campos del documento', () {
      final usuario = UsuarioApp.fromFirestore('uid123', {
        'correo': 'admin@rocakids.org',
        'nombre': 'Admin Prueba',
        'rol': 'administrador',
      });

      expect(usuario.uid, 'uid123');
      expect(usuario.correo, 'admin@rocakids.org');
      expect(usuario.nombre, 'Admin Prueba');
      expect(usuario.rol, RolUsuario.administrador);
    });
  });
}

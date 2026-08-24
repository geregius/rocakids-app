import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre el marcador del celular con [telefono] ya escrito (2026-08-24,
/// pedido de Rafael: botón de llamar directo desde la ficha del niño).
/// En navegador de escritorio depende de si el sistema operativo tiene
/// algo asociado al esquema `tel:` (normalmente no pasa nada visible);
/// en celular abre la app de teléfono de siempre.
Future<void> llamarTelefono(BuildContext context, String telefono) async {
  final numero = telefono.replaceAll(RegExp(r'[^0-9+]'), '');
  if (numero.isEmpty) return;
  final uri = Uri(scheme: 'tel', path: numero);
  try {
    final abrio = await launchUrl(uri);
    if (!abrio && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir el marcador para $telefono.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir el marcador: $e')));
    }
  }
}

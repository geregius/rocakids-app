import 'dart:convert';

import 'package:http/http.dart' as http;

/// Extrae el ID de video de cualquier formato común de enlace de
/// YouTube (`watch?v=`, `youtu.be/`, `shorts/`, `embed/`), con o sin
/// parámetros extra (`&t=`, `&list=`, etc.). `null` si no se reconoce.
String? extraerIdYoutube(String url) {
  final texto = url.trim();
  if (texto.isEmpty) return null;

  final patrones = [
    RegExp(r'(?:youtu\.be/)([\w-]{11})'),
    RegExp(r'(?:youtube\.com/watch\?.*v=)([\w-]{11})'),
    RegExp(r'(?:youtube\.com/shorts/)([\w-]{11})'),
    RegExp(r'(?:youtube\.com/embed/)([\w-]{11})'),
    RegExp(r'(?:youtube\.com/live/)([\w-]{11})'),
  ];
  for (final patron in patrones) {
    final match = patron.firstMatch(texto);
    if (match != null) return match.group(1);
  }
  return null;
}

/// Trae el título REAL del video directamente desde YouTube (endpoint
/// público `oembed`, sin necesitar API key ni cuota) — así el video
/// queda "nombrado como está en YouTube" sin que alguien tenga que
/// copiarlo a mano. Se llama una sola vez, al crear o editar el video
/// (no en cada carga de "Video Tutoriales" — eso sí sumaría una llamada
/// externa por video, cada vez que alguien abre la pantalla).
Future<String> obtenerTituloYoutube(String youtubeUrl) async {
  final oembedUrl = Uri.parse(
    'https://www.youtube.com/oembed?format=json&url=${Uri.encodeComponent(youtubeUrl)}',
  );
  final respuesta = await http.get(oembedUrl);
  if (respuesta.statusCode != 200) {
    throw Exception(
      'No se pudo obtener el video de YouTube — revisa que el enlace sea '
      'correcto y que el video sea público o "no listado".',
    );
  }
  final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
  return (datos['title'] as String?)?.trim() ?? '';
}

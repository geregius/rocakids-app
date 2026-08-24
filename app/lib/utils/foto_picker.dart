import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';

/// Lado máximo (en píxeles) al que se redimensiona cualquier foto antes
/// de guardarla. De sobra para una foto de perfil/seguridad mostrada en
/// la app, y deja el archivo muy por debajo del límite de 5MB que exige
/// `storage.rules`.
const _ladoMaximoFoto = 1600;
const _calidadJpg = 82;

/// Resultado de elegir/tomar una foto: bytes ya redimensionados y
/// recomprimidos a JPEG, listos para subir a Storage.
class FotoElegida {
  final Uint8List bytes;
  final String extension;
  const FotoElegida(this.bytes, this.extension);
}

/// Muestra un selector con las dos opciones (tomar foto / elegir de la
/// galería), procesa la foto elegida (ver [_procesar]) y la devuelve
/// lista para subir, o null si canceló o la foto no se pudo procesar.
Future<FotoElegida?> elegirFotoConCamaraOGaleria(BuildContext context) async {
  final origen = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera, color: AppColors.azulMarino),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppColors.azulMarino),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (origen == null || !context.mounted) return null;
  final archivo = await ImagePicker().pickImage(source: origen);
  if (archivo == null) return null;
  if (!context.mounted) return null;
  return _procesar(context, archivo);
}

/// Toma una foto SOLO con la cámara, sin ofrecer la galería — para
/// evidencia que debe capturarse en el momento (ej. "Modo emergencia",
/// 2026-08-19): dejar elegir una foto ya guardada anularía el propósito
/// de verificar quién está ahí en ese instante.
Future<FotoElegida?> tomarFotoConCamara(BuildContext context) async {
  final archivo = await ImagePicker().pickImage(source: ImageSource.camera);
  if (archivo == null) return null;
  if (!context.mounted) return null;
  return _procesar(context, archivo);
}

/// Lee los bytes del archivo elegido y los redimensiona/recomprime
/// (2026-08-24, corrige bug reportado por Rafael: una foto pesada de la
/// galería — 8-15MB es normal en un celular moderno — se quedaba
/// "trabada" al guardar, sin mostrar ningún error, porque `storage.
/// rules` la rechazaba por superar 5MB. En Flutter Web además el
/// parámetro `imageQuality` de `image_picker` no tiene ningún efecto —
/// la implementación web del plugin lo ignora — así que sin este paso
/// la foto SIEMPRE llegaba a Storage en su tamaño original). Si la
/// imagen no se puede decodificar (formato no soportado, ej. HEIC sin
/// convertir), avisa con un SnackBar en vez de fallar en silencio.
Future<FotoElegida?> _procesar(BuildContext context, XFile archivo) async {
  try {
    final original = await archivo.readAsBytes();
    final comprimida = await _comprimir(original);
    return FotoElegida(comprimida, 'jpg');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo usar esa foto. Prueba con otra imagen (JPG o PNG).',
          ),
        ),
      );
    }
    return null;
  }
}

Future<Uint8List> _comprimir(Uint8List original) {
  // decodeImage/encodeJpg son CPU-intensivos y síncronos; se envuelven
  // en un microtask (`Future(...)`) para no bloquear el frame actual
  // antes de que la UI pueda pintar cualquier estado de carga.
  return Future(() {
    final decodificada = img.decodeImage(original);
    if (decodificada == null) {
      throw const FormatException('Formato de imagen no soportado.');
    }
    final necesitaRedimension =
        decodificada.width > _ladoMaximoFoto || decodificada.height > _ladoMaximoFoto;
    final lista = necesitaRedimension
        ? img.copyResize(
            decodificada,
            width: decodificada.width >= decodificada.height ? _ladoMaximoFoto : null,
            height: decodificada.height > decodificada.width ? _ladoMaximoFoto : null,
          )
        : decodificada;
    return Uint8List.fromList(img.encodeJpg(lista, quality: _calidadJpg));
  });
}

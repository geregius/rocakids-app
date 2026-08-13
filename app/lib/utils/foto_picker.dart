import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';

/// Muestra un selector con las dos opciones (tomar foto / elegir de la
/// galería) y devuelve el archivo elegido, o null si canceló. Pensado
/// sobre todo para navegador móvil, donde "tomar foto" abre la cámara
/// del dispositivo directamente.
Future<XFile?> elegirFotoConCamaraOGaleria(BuildContext context) async {
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
  return ImagePicker().pickImage(source: origen, imageQuality: 80);
}

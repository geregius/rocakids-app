import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Tema visual de RocaKids: paleta de marca + tipografía Fredoka
/// (sustituto libre de VAG Rounded BT, la fuente del logo oficial).
class AppTheme {
  AppTheme._();

  static Color _elevatedBackground(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) return Colors.grey.shade300;
    if (states.contains(WidgetState.pressed)) return AppColors.purpura;
    if (states.contains(WidgetState.hovered)) return AppColors.amarillo;
    return AppColors.azulMarino;
  }

  static Color _elevatedForeground(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) return Colors.grey.shade600;
    // Texto oscuro sobre el fondo amarillo del hover para que se lea bien.
    if (states.contains(WidgetState.hovered) && !states.contains(WidgetState.pressed)) {
      return AppColors.textoPrincipal;
    }
    return Colors.white;
  }

  static Color _outlinedOverlay(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return AppColors.purpura.withValues(alpha: 0.18);
    }
    if (states.contains(WidgetState.hovered)) {
      return AppColors.amarillo.withValues(alpha: 0.25);
    }
    return Colors.transparent;
  }

  static Color _lightOverlayOnDark(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) return Colors.white24;
    if (states.contains(WidgetState.hovered)) return Colors.white12;
    return Colors.transparent;
  }

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.azulMarino,
        primary: AppColors.azulMarino,
        secondary: AppColors.amarillo,
        error: AppColors.rojo,
        surface: AppColors.superficie,
      ),
      scaffoldBackgroundColor: AppColors.fondo,
      textTheme: GoogleFonts.fredokaTextTheme(),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.azulMarino,
        foregroundColor: Colors.white,
        titleTextStyle: GoogleFonts.fredoka(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(_elevatedBackground),
          foregroundColor: WidgetStateProperty.resolveWith(_elevatedForeground),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.fredoka(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.azulMarino),
          overlayColor: WidgetStateProperty.resolveWith(_outlinedOverlay),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.azulMarino, width: 1.5)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.fredoka(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.azulMarino),
          overlayColor: WidgetStateProperty.resolveWith(_outlinedOverlay),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: WidgetStateProperty.resolveWith(_lightOverlayOnDark),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        prefixIconColor: AppColors.azulMarino,
        suffixIconColor: AppColors.azulMarino,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.azulMarino, width: 2),
        ),
      ),
    );
  }
}

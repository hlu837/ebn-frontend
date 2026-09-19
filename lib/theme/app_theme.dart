import 'package:flutter/material.dart';

/// Centralized design tokens for the platform.
/// Aesthetic: premium asset-marketplace — signal-red accent (matching the
/// landing page and visitor dashboard), deep charcoal/black ink for text,
/// generous rounded corners, confident bold typography.
class AppColors {
  AppColors._();

  static const Color primaryYellow = Color(0xFFFF2636); // signal accent (vivid red)
  static const Color primaryYellowDark = Color(0xFFC7301C);
  static const Color ink = Color(0xFF14140F); // near-black surfaces/text
  static const Color inkSoft = Color(0xFF2A2A22);
  static const Color slate = Color(0xFF6B6B60); // secondary text
  static const Color cloud = Color(0xFFFFFFFF); // app background (white)
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE7E4D9);
  static const Color success = Color(0xFF1FAA59);
  static const Color danger = Color(0xFFE14B4B);

  // ── Dark-mode counterparts ────────────────────────────────────────
  // NOTE: these back `AppTheme.dark` (below) and anything reading colors
  // through `Theme.of(context)`. Screens/widgets that reference the
  // *light* constants above directly (`AppColors.ink`, `AppColors.cloud`,
  // etc. — the vast majority of this codebase) do not consult the active
  // theme and will keep rendering with the light palette even when the
  // app is switched to dark mode. Migrating those call sites to pull
  // from `Theme.of(context)` instead is a separate, larger follow-up.
  static const Color inkDark = Color(0xFFF2F1EA); // near-white text on dark surfaces
  static const Color inkSoftDark = Color(0xFFD8D6C9);
  static const Color slateDark = Color(0xFF9C9A8E);
  static const Color cloudDark = Color(0xFF121210); // app background (near-black)
  static const Color cardDark = Color(0xFF1C1C19);
  static const Color borderDark = Color(0xFF33332D);
}

class AppRadii {
  AppRadii._();
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double pill = 100;
  /// Buttons specifically — a clean, moderately-rounded rectangle rather
  /// than a full stadium/pill shape, which read as oversized and informal
  /// at the 50–56px button heights used throughout the app. Badges, tags,
  /// and chips keep using [pill].
  static const double button = 14;
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, fontFamily: 'Manrope');

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.cloud,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.ink,
        secondary: AppColors.primaryYellow,
        surface: AppColors.card,
        error: AppColors.danger,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ).copyWith(
        displayLarge: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          height: 1.15,
          letterSpacing: -0.5,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.3,
        ),
        titleMedium: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
          height: 1.4,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.slate,
          height: 1.4,
        ),
        labelLarge: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white, // was primaryYellow — red text on a black button read as a mistake, not a style
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: AppColors.ink, width: 1.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.slate, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
        hintStyle: const TextStyle(color: AppColors.slate, fontWeight: FontWeight.w500),
        labelStyle: const TextStyle(color: AppColors.slate, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.ink),
        actionsIconTheme: IconThemeData(color: AppColors.ink),
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        // Thin red accent line under every app bar — keeps the header
        // white/on-brand while still visually separating it from the body.
        shape: Border(bottom: BorderSide(color: AppColors.primaryYellow, width: 3)),
      ),
    );
  }

  /// Dark counterpart of [light]. Mirrors the same structure/tokens with
  /// the dark palette from [AppColors] swapped in. See the note on the
  /// dark-mode color constants above: this covers default Material
  /// widgets and anything that reads `Theme.of(context)`, but most of
  /// this codebase's screens are styled directly with the light
  /// `AppColors` constants and won't re-skin until they're migrated too.
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Manrope',
      brightness: Brightness.dark,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.cloudDark,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: AppColors.inkDark,
        secondary: AppColors.primaryYellow,
        surface: AppColors.cardDark,
        error: AppColors.danger,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.inkDark,
        displayColor: AppColors.inkDark,
      ).copyWith(
        displayLarge: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: AppColors.inkDark,
          height: 1.15,
          letterSpacing: -0.5,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.inkDark,
          letterSpacing: -0.3,
        ),
        titleMedium: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.inkDark,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.inkDark,
          height: 1.4,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.slateDark,
          height: 1.4,
        ),
        labelLarge: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.inkDark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.inkDark,
          foregroundColor: AppColors.cloudDark,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkDark,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: AppColors.inkDark, width: 1.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.slateDark, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
        hintStyle: const TextStyle(color: AppColors.slateDark, fontWeight: FontWeight.w500),
        labelStyle: const TextStyle(color: AppColors.slateDark, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cloudDark,
        foregroundColor: AppColors.inkDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.inkDark),
        actionsIconTheme: IconThemeData(color: AppColors.inkDark),
        titleTextStyle: TextStyle(
          color: AppColors.inkDark,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        shape: Border(bottom: BorderSide(color: AppColors.primaryYellow, width: 3)),
      ),
    );
  }
}

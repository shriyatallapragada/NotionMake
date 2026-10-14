import 'package:flutter/material.dart';

/// The app's palette. All of the app's own colors live here, so restyling is a
/// one-file change. (Notion block colors in the preview are separate: they
/// imitate how Notion draws its own colors.)
class AppColors {
  // Base
  static const background = Color(0xFFEAE8DF);
  static const card = Color(0xFFF2F1EC);
  static const ink = Color(0xFF1C1C1C);

  // Primary accents
  static const rose = Color(0xFFA6535A);
  static const terracotta = Color(0xFFDE5E3B);
  static const periwinkle = Color(0xFF8A96D6);
  static const sage = Color(0xFFA1CA81);
  static const slate = Color(0xFF3A3A3C);

  // Secondary accents
  static const navy = Color(0xFF2B5876);
  static const teal = Color(0xFF44A1B2);
  static const yellow = Color(0xFFD8CD4C);

  // Derived, for accessibility (contrast checked against background and card):
  /// Rose is 4.3:1 as text on the background; this deeper shade is 5.5:1.
  static const roseText = Color(0xFF8F444B);
  static const mutedText = Color(0xFF5A5A5C);
  static const outline = Color(0xFF7A7A76);
  static const outlineVariant = Color(0xFFCFCDC2);

  // Dark mode (derived from the same palette)
  static const darkBackground = Color(0xFF1C1C1C);
  static const darkCard = Color(0xFF2A2A2C);
  static const darkInk = Color(0xFFEAE8DF);
  static const darkRose = Color(0xFFD98A91);
  static const darkOutline = Color(0xFF8B8B86);
  static const darkOutlineVariant = Color(0xFF444446);
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? AppColors.darkBackground : AppColors.background;
  final card = dark ? AppColors.darkCard : AppColors.card;
  final ink = dark ? AppColors.darkInk : AppColors.ink;
  final outline = dark ? AppColors.darkOutline : AppColors.outline;
  final divider = dark ? AppColors.darkOutlineVariant : AppColors.outlineVariant;

  final scheme = ColorScheme(
    brightness: brightness,
    // Dark Slate buttons with cream text (10:1) in light mode; periwinkle in dark.
    primary: dark ? AppColors.periwinkle : AppColors.slate,
    onPrimary: dark ? AppColors.ink : AppColors.card,
    primaryContainer: AppColors.periwinkle,
    onPrimaryContainer: AppColors.ink,
    // Terracotta is a fill color with dark text on top (4.7:1), never text.
    secondary: AppColors.terracotta,
    onSecondary: AppColors.ink,
    secondaryContainer: dark ? AppColors.slate : AppColors.sage,
    onSecondaryContainer: dark ? AppColors.darkInk : AppColors.ink,
    tertiary: dark ? AppColors.teal : AppColors.navy,
    onTertiary: dark ? AppColors.ink : AppColors.card,
    tertiaryContainer: AppColors.teal,
    onTertiaryContainer: AppColors.ink,
    error: dark ? AppColors.darkRose : AppColors.roseText,
    onError: dark ? AppColors.ink : AppColors.card,
    errorContainer: AppColors.rose,
    onErrorContainer: AppColors.card,
    surface: bg,
    onSurface: ink,
    onSurfaceVariant: dark ? const Color(0xFFB8B6AD) : AppColors.mutedText,
    outline: outline,
    outlineVariant: divider,
    surfaceContainerLowest: bg,
    surfaceContainerLow: card,
    surfaceContainer: card,
    surfaceContainerHigh: card,
    surfaceContainerHighest: dark ? AppColors.slate : AppColors.card,
    inverseSurface: dark ? AppColors.darkInk : AppColors.slate,
    onInverseSurface: dark ? AppColors.ink : AppColors.card,
    inversePrimary: AppColors.periwinkle,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    dividerTheme: DividerThemeData(color: divider, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      shape: Border(bottom: BorderSide(color: divider)),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: divider),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderSide: BorderSide(color: outline)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: outline)),
      // Navy focus ring: 6:1 against the cream surfaces.
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: dark ? AppColors.periwinkle : AppColors.navy, width: 2),
      ),
      errorBorder: OutlineInputBorder(borderSide: BorderSide(color: scheme.error)),
      focusedErrorBorder: OutlineInputBorder(borderSide: BorderSide(color: scheme.error, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: rounded)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: rounded,
        side: BorderSide(color: outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: rounded)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.terracotta,
      foregroundColor: AppColors.ink,
      elevation: 2,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: card,
      selectedColor: scheme.secondaryContainer,
      side: BorderSide(color: divider),
      labelStyle: TextStyle(color: ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: card,
        foregroundColor: ink,
        selectedBackgroundColor: scheme.secondaryContainer,
        selectedForegroundColor: scheme.onSecondaryContainer,
        side: BorderSide(color: outline),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: ink,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: AppColors.terracotta,
      dividerColor: divider,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: divider),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      // Sage on Dark Slate is 6.1:1.
      actionTextColor: dark ? AppColors.slate : AppColors.sage,
      shape: rounded,
    ),
    bannerTheme: MaterialBannerThemeData(
      // Muted Yellow with dark text is 10:1.
      backgroundColor: AppColors.yellow,
      contentTextStyle: const TextStyle(color: AppColors.ink),
      surfaceTintColor: Colors.transparent,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.terracotta),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.primary : null,
      ),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      side: BorderSide(color: outline, width: 1.5),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(scheme.primary)),
    listTileTheme: ListTileThemeData(iconColor: ink, textColor: ink),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
    ),
  );
}

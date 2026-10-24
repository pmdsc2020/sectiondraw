// SectionDraw design system: colour tokens, typography and Material themes
// for light and dark mode. Every text/background pair used by the app is
// chosen for at least WCAG AA contrast (4.5:1 for body text).

import 'package:flutter/material.dart';

const String kBodyFont = 'Inter';
const String kDisplayFont = 'SpaceGrotesk';

/// App-specific colour tokens that Material's ColorScheme does not cover.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bgTop,
    required this.bgBottom,
    required this.blobA,
    required this.blobB,
    required this.blobC,
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.text,
    required this.muted,
    required this.good,
    required this.fair,
    required this.poor,
    required this.idle,
    required this.water,
    required this.earth,
    required this.accent,
    required this.danger,
    required this.glow,
    required this.brandGradient,
  });

  final Color bgTop;
  final Color bgBottom;

  /// Soft "aurora" blobs drawn behind the glass surfaces.
  final Color blobA;
  final Color blobB;
  final Color blobC;

  /// Translucent fill and hairline border of glass cards.
  final Color glass;
  final Color glassStrong;
  final Color glassBorder;

  final Color text;

  /// Secondary text; still >= 4.5:1 on [bgTop], [bgBottom] and [glass].
  final Color muted;

  /// GPS status fills. White text on each is >= 4.5:1.
  final Color good;
  final Color fair;
  final Color poor;
  final Color idle;

  /// Lowest point / water.
  final Color water;

  /// Ground line.
  final Color earth;
  final Color accent;
  final Color danger;
  final Color glow;
  final List<Color> brandGradient;

  static const light = AppColors(
    bgTop: Color(0xFFF2F7F4),
    bgBottom: Color(0xFFE6EFEA),
    blobA: Color(0x5534D399),
    blobB: Color(0x4438BDF8),
    blobC: Color(0x33F59E0B),
    glass: Color(0xB8FFFFFF),
    glassStrong: Color(0xE6FFFFFF),
    glassBorder: Color(0x1F0F3D2A),
    text: Color(0xFF0B1A12),
    muted: Color(0xFF45574D),
    good: Color(0xFF15803D),
    fair: Color(0xFFB45309),
    poor: Color(0xFFB91C1C),
    idle: Color(0xFF475569),
    water: Color(0xFF0369A1),
    earth: Color(0xFF7C4A2D),
    accent: Color(0xFFB45309),
    danger: Color(0xFFB91C1C),
    glow: Color(0x5510B981),
    brandGradient: [Color(0xFF047857), Color(0xFF0E7490)],
  );

  static const dark = AppColors(
    bgTop: Color(0xFF07110D),
    bgBottom: Color(0xFF0B1A1F),
    blobA: Color(0x4410B981),
    blobB: Color(0x3306B6D4),
    blobC: Color(0x22F59E0B),
    glass: Color(0x991A2A23),
    glassStrong: Color(0xE0142019),
    glassBorder: Color(0x26D1FAE5),
    text: Color(0xFFE8F3EE),
    muted: Color(0xFFA3B8AD),
    good: Color(0xFF15803D),
    fair: Color(0xFFB45309),
    poor: Color(0xFFB91C1C),
    idle: Color(0xFF475569),
    water: Color(0xFF38BDF8),
    earth: Color(0xFFD6A77A),
    accent: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    glow: Color(0x6634D399),
    brandGradient: [Color(0xFF10B981), Color(0xFF06B6D4)],
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bgTop: c(bgTop, other.bgTop),
      bgBottom: c(bgBottom, other.bgBottom),
      blobA: c(blobA, other.blobA),
      blobB: c(blobB, other.blobB),
      blobC: c(blobC, other.blobC),
      glass: c(glass, other.glass),
      glassStrong: c(glassStrong, other.glassStrong),
      glassBorder: c(glassBorder, other.glassBorder),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      good: c(good, other.good),
      fair: c(fair, other.fair),
      poor: c(poor, other.poor),
      idle: c(idle, other.idle),
      water: c(water, other.water),
      earth: c(earth, other.earth),
      accent: c(accent, other.accent),
      danger: c(danger, other.danger),
      glow: c(glow, other.glow),
      brandGradient: [
        for (var i = 0; i < brandGradient.length; i++)
          c(brandGradient[i], other.brandGradient[i]),
      ],
    );
  }
}

extension AppThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Display text in Space Grotesk (variable font: weight set by axis too).
TextStyle display(double size,
    {FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = -0.5,
    double? height}) {
  return TextStyle(
    fontFamily: kDisplayFont,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );
}

/// Numbers that should not jitter while they change (GPS readings).
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];

/// Small all-caps label used above values.
TextStyle eyebrow(Color color) => TextStyle(
      fontFamily: kBodyFont,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.1,
      color: color,
    );

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final c = dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF059669),
    brightness: b,
  ).copyWith(
    primary: dark ? const Color(0xFF34D399) : const Color(0xFF047857),
    onPrimary: dark ? const Color(0xFF022C1E) : Colors.white,
    secondary: dark ? const Color(0xFF22D3EE) : const Color(0xFF0E7490),
    onSecondary: dark ? const Color(0xFF032830) : Colors.white,
    error: c.danger,
    surface: dark ? const Color(0xFF0F1C17) : Colors.white,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    outline: dark ? const Color(0xFF4B6357) : const Color(0xFF8AA197),
    outlineVariant: c.glassBorder,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: kBodyFont,
  );

  final tt = base.textTheme.apply(
    fontFamily: kBodyFont,
    bodyColor: c.text,
    displayColor: c.text,
  );
  final textTheme = tt.copyWith(
    displaySmall: display(34, color: c.text),
    headlineMedium: display(28, color: c.text),
    headlineSmall: display(24, color: c.text),
    titleLarge: display(21,
        weight: FontWeight.w600, color: c.text, letterSpacing: -0.2),
    titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: tt.bodyLarge?.copyWith(fontSize: 16.5, height: 1.4),
    bodyMedium: tt.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
    labelLarge: tt.labelLarge?.copyWith(
        fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
  );

  final radius = BorderRadius.circular(16);

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: c.bgTop,
    extensions: [c],
    // Apple platforms keep Flutter's default transition; newer Flutter
    // versions no longer export the Cupertino builder from material.dart.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(22, color: c.text),
    ),
    cardTheme: CardThemeData(
      color: c.glassStrong,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.glassBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF12201A) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: c.glassBorder),
      ),
      titleTextStyle: display(22, color: c.text),
      contentTextStyle: TextStyle(
          fontFamily: kBodyFont, fontSize: 16, height: 1.45, color: c.text),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? const Color(0xFF15241D) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.glassBorder),
      ),
      textStyle: TextStyle(
          fontFamily: kBodyFont,
          fontSize: 15.5,
          fontWeight: FontWeight.w500,
          color: c.text),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFE8F3EE) : const Color(0xFF0B1A12),
      contentTextStyle: TextStyle(
        fontFamily: kBodyFont,
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        color: dark ? const Color(0xFF0B1A12) : Colors.white,
      ),
      actionTextColor: dark ? const Color(0xFF047857) : const Color(0xFF6EE7B7),
      shape: RoundedRectangleBorder(borderRadius: radius),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.glassStrong,
      labelStyle: TextStyle(color: c.muted, fontWeight: FontWeight.w500),
      floatingLabelStyle:
          TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: c.muted),
      helperStyle: TextStyle(color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outline.withAlpha(150)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.danger, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(
            fontFamily: kBodyFont, fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: c.text,
        side: BorderSide(color: scheme.outline),
        textStyle: const TextStyle(
            fontFamily: kBodyFont, fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(
            fontFamily: kBodyFont, fontSize: 15.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: c.glassStrong,
        foregroundColor: c.text,
        selectedBackgroundColor: scheme.primary,
        selectedForegroundColor: scheme.onPrimary,
        side: BorderSide(color: scheme.outline.withAlpha(150)),
        textStyle: const TextStyle(
            fontFamily: kBodyFont, fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFFE8F3EE) : const Color(0xFF0B1A12),
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: TextStyle(
        fontFamily: kBodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: dark ? const Color(0xFF0B1A12) : Colors.white,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: c.glassBorder,
    ),
    dividerTheme: DividerThemeData(color: c.glassBorder, space: 1),
  );
}

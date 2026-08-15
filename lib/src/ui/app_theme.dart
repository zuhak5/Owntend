import 'package:flutter/material.dart';

class HkColors {
  const HkColors._();

  static const appBackground = Color(0xFFF7F9FC);
  static const appSurface = Color(0xFFFFFFFF);
  static const appSurfaceMuted = Color(0xFFF1F4F7);
  static const appSurfaceGreen = Color(0xFFDDF7E5);
  static const appPrimary = Color(0xFF22B953);
  static const appPrimaryDark = Color(0xFF119B42);
  static const appPrimaryMuted = Color(0xFFDDF7E5);
  static const appTextPrimary = Color(0xFF10213A);
  static const appTextSecondary = Color(0xFF526174);
  static const appTextTertiary = Color(0xFF7F8A99);
  static const appBorder = Color(0xFFDDE3EA);
  static const appBorderStrong = Color(0xFFDDE3EA);
  static const disabled = Color(0xFFB8C0CA);
  static const appDanger = Color(0xFFC7382E);
  static const appDangerSurface = Color(0xFFF8EAEA);
  static const appWarning = Color(0xFFC58A14);
  static const appWarningSurface = Color(0xFFFFF2D5);
  static const appInfo = Color(0xFF4967A9);
  static const appInfoSurface = Color(0xFFE8EDF8);

  static const surface = appBackground;
  static const surfaceDim = Color(0xFFE9EDF2);
  static const surfaceContainerLowest = appSurface;
  static const surfaceContainerLow = appSurfaceMuted;
  static const surfaceContainer = Color(0xFFF1F4F7);
  static const surfaceContainerHigh = Color(0xFFE9EDF2);
  static const surfaceContainerHighest = Color(0xFFDDE3EA);
  static const onSurface = appTextPrimary;
  static const onSurfaceVariant = appTextSecondary;
  static const outline = appTextTertiary;
  static const outlineVariant = appBorderStrong;
  static const primary = appPrimary;
  static const primaryContainer = appPrimaryMuted;
  static const onPrimaryContainer = Color(0xFF064D29);
  static const primaryFixed = appPrimaryMuted;
  static const primaryFixedDim = Color(0xFFB7EDC8);
  static const secondary = appTextSecondary;
  static const secondaryContainer = appPrimaryMuted;
  static const secondaryFixed = appSurfaceGreen;
  static const onSecondaryFixed = appPrimaryDark;
  static const tertiary = appWarning;
  static const tertiaryContainer = appWarning;
  static const tertiaryFixed = appWarningSurface;
  static const tertiaryFixedDim = Color(0xFFE8C069);
  static const error = appDanger;
  static const errorContainer = appDangerSurface;
  static const onErrorContainer = Color(0xFF7B2222);

  static const green = appPrimary;
  static const amber = appWarning;
  static const indigo = appInfo;
  static const mint = appPrimaryMuted;

  static const teal = primary;
  static const tealDark = Color(0xFF064D29);
  static const cyan = primaryFixedDim;
  static const graphite = onSurface;
  static const graphiteMuted = onSurfaceVariant;
  static const porcelain = surface;
  static const surfaceAlt = surfaceContainer;
  static const line = outlineVariant;
  static const red = error;

  // Header badge tokens (spec: badge_green_bg / badge_green_icon)
  static const headerBadgeGreenBg = Color(0xFFECFDF5);
  static const headerBadgeGreenIcon = Color(0xFF10B981);
}

class HkSpacing {
  const HkSpacing._();

  static const space2 = 2.0;
  static const base = 4.0;
  static const space4 = 4.0;
  static const space6 = 6.0;
  static const xs = 8.0;
  static const space8 = 8.0;
  static const sm = 12.0;
  static const space12 = 12.0;
  static const md = 16.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const lg = 20.0;
  static const space24 = 24.0;
  static const xl = 24.0;
  static const space32 = 32.0;
  static const space40 = 40.0;
  static const xxl = 32.0;
  static const space48 = 48.0;
  static const gutter = 16.0;
  static const bottomNav = 58.0;
  static const bottomAction = 76.0;
}

class HkRadii {
  const HkRadii._();

  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const xl = 22.0;
  static const xxl = 28.0;
  static const sheet = 28.0;
  static const full = 999.0;
}

class HkShadows {
  const HkShadows._();

  static List<BoxShadow> ambient({Color tint = HkColors.appTextPrimary}) => [
    BoxShadow(
      color: tint.withValues(alpha: 0.10),
      blurRadius: 30,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: HkColors.appTextPrimary.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class HkSnackBarColors extends ThemeExtension<HkSnackBarColors> {
  const HkSnackBarColors({
    required this.surface,
    required this.foreground,
    required this.action,
    required this.progressTrack,
    required this.progressFill,
  });

  final Color surface;
  final Color foreground;
  final Color action;
  final Color progressTrack;
  final Color progressFill;

  static HkSnackBarColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<HkSnackBarColors>() ??
        HkSnackBarColors.fromScheme(
          theme.colorScheme,
          isDark: theme.brightness == Brightness.dark,
        );
  }

  static HkSnackBarColors fromScheme(
    ColorScheme scheme, {
    required bool isDark,
  }) {
    final surface = isDark
        ? scheme.surfaceContainerHighest
        : scheme.inverseSurface;
    final foreground = isDark ? scheme.onSurface : scheme.onInverseSurface;
    final action = _contrastRatio(scheme.primary, surface) >= 4.5
        ? scheme.primary
        : foreground;
    return HkSnackBarColors(
      surface: surface,
      foreground: foreground,
      action: action,
      progressTrack: Color.alphaBlend(
        foreground.withValues(alpha: 0.40),
        surface,
      ),
      progressFill: foreground,
    );
  }

  @override
  HkSnackBarColors copyWith({
    Color? surface,
    Color? foreground,
    Color? action,
    Color? progressTrack,
    Color? progressFill,
  }) {
    return HkSnackBarColors(
      surface: surface ?? this.surface,
      foreground: foreground ?? this.foreground,
      action: action ?? this.action,
      progressTrack: progressTrack ?? this.progressTrack,
      progressFill: progressFill ?? this.progressFill,
    );
  }

  @override
  HkSnackBarColors lerp(ThemeExtension<HkSnackBarColors>? other, double t) {
    if (other is! HkSnackBarColors) {
      return this;
    }
    return HkSnackBarColors(
      surface: Color.lerp(surface, other.surface, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      action: Color.lerp(action, other.action, t)!,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      progressFill: Color.lerp(progressFill, other.progressFill, t)!,
    );
  }
}

double _contrastRatio(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lightest = aLum > bLum ? aLum : bLum;
  final darkest = aLum > bLum ? bLum : aLum;
  return (lightest + 0.05) / (darkest + 0.05);
}

class OwntendTheme {
  const OwntendTheme._();

  static const _fontFallback = <String>[
    'Noto Sans Arabic',
    'Noto Naskh Arabic',
    'sans-serif',
  ];

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: HkColors.primary,
      onPrimary: Colors.white,
      primaryContainer: HkColors.primaryContainer,
      onPrimaryContainer: HkColors.onPrimaryContainer,
      secondary: HkColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: HkColors.secondaryContainer,
      onSecondaryContainer: Color(0xFF576565),
      tertiary: HkColors.appWarning,
      onTertiary: Colors.white,
      tertiaryContainer: HkColors.tertiaryContainer,
      onTertiaryContainer: Color(0xFFFFEBE6),
      error: HkColors.error,
      onError: Colors.white,
      errorContainer: HkColors.errorContainer,
      onErrorContainer: HkColors.onErrorContainer,
      surface: HkColors.surface,
      onSurface: HkColors.onSurface,
      surfaceDim: HkColors.surfaceDim,
      surfaceBright: HkColors.surface,
      surfaceContainerLowest: HkColors.surfaceContainerLowest,
      surfaceContainerLow: HkColors.surfaceContainerLow,
      surfaceContainer: HkColors.surfaceContainer,
      surfaceContainerHigh: HkColors.surfaceContainerHigh,
      surfaceContainerHighest: HkColors.surfaceContainerHighest,
      onSurfaceVariant: HkColors.onSurfaceVariant,
      outline: HkColors.outline,
      outlineVariant: HkColors.outlineVariant,
      shadow: HkColors.appTextPrimary,
      scrim: Colors.black,
      inverseSurface: HkColors.appTextPrimary,
      onInverseSurface: Color(0xFFF2F1EC),
      inversePrimary: HkColors.primaryFixedDim,
      surfaceTint: HkColors.appPrimary,
    );
    return _fromScheme(scheme, isDark: false);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF54DA88),
      onPrimary: Color(0xFF032B17),
      primaryContainer: Color(0xFF104F2D),
      onPrimaryContainer: Color(0xFFC5F8D6),
      secondary: Color(0xFFB9CAC0),
      onSecondary: Color(0xFF1C3528),
      secondaryContainer: Color(0xFF284537),
      onSecondaryContainer: Color(0xFFD4EBDD),
      tertiary: Color(0xFFFFB4A4),
      onTertiary: Color(0xFF561F12),
      tertiaryContainer: Color(0xFF7D2C1A),
      onTertiaryContainer: Color(0xFFFFDAD2),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF0D2118),
      onSurface: Color(0xFFF4F8F5),
      surfaceDim: Color(0xFF071510),
      surfaceBright: Color(0xFF173126),
      surfaceContainerLowest: Color(0xFF0A1C15),
      surfaceContainerLow: Color(0xFF101F18),
      surfaceContainer: Color(0xFF112A1F),
      surfaceContainerHigh: Color(0xFF173126),
      surfaceContainerHighest: Color(0xFF234034),
      onSurfaceVariant: Color(0xFFAAB8B0),
      outline: Color(0xFF315344),
      outlineVariant: Color(0xFF234034),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFE3E3DE),
      onInverseSurface: Color(0xFF30312E),
      inversePrimary: HkColors.primary,
      surfaceTint: Color(0xFF54DA88),
    );
    return _fromScheme(scheme, isDark: true);
  }

  static ThemeData _fromScheme(ColorScheme scheme, {required bool isDark}) {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Geist',
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );
    final textTheme = _textTheme(scheme)
        .apply(fontFamilyFallback: _fontFallback);
    final snackBarColors = HkSnackBarColors.fromScheme(scheme, isDark: isDark);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(HkRadii.md),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return base.copyWith(
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[snackBarColors],
      textTheme: textTheme,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 56,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontFamilyFallback: _fontFallback,
          fontSize: 20,
          height: 24 / 20,
          letterSpacing: 0,
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HkRadii.xl),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.32 : 1),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: HkColors.disabled,
          disabledForegroundColor: HkColors.appTextSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HkRadii.full),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          backgroundColor: scheme.surfaceContainerLowest,
          foregroundColor: scheme.primary,
          disabledForegroundColor: HkColors.appTextTertiary,
          side: BorderSide(color: scheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HkRadii.full),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HkSpacing.sm,
          vertical: HkSpacing.xs,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HkRadii.md),
        ),
        sizeConstraints: const BoxConstraints.tightFor(width: 48, height: 48),
        extendedSizeConstraints: const BoxConstraints.tightFor(
          width: 136,
          height: 48,
        ),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 12),
        extendedIconLabelSpacing: 6,
        extendedTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      listTileTheme: ListTileThemeData(
        dense: true,
        minLeadingWidth: 30,
        horizontalTitleGap: 8,
        minVerticalPadding: 4,
        contentPadding: EdgeInsets.zero,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(HkRadii.sheet),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLowest,
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.primary,
          foregroundColor: scheme.onSurfaceVariant,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HkRadii.md),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HkRadii.md),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: snackBarColors.surface,
        actionTextColor: snackBarColors.action,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: snackBarColors.foreground,
        ),
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HkRadii.md),
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    const family = 'Geist';
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: family,
        fontSize: 20,
        height: 24 / 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: family,
        fontSize: 20,
        height: 24 / 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: family,
        fontSize: 18,
        height: 22 / 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: family,
        fontSize: 16,
        height: 20 / 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: family,
        fontSize: 15,
        height: 19 / 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: family,
        fontSize: 14,
        height: 18 / 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: family,
        fontSize: 13,
        height: 17 / 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: family,
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: family,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: family,
        fontSize: 11,
        height: 14 / 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontFamily: family,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: family,
        fontSize: 11,
        height: 14 / 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontFamily: family,
        fontSize: 10,
        height: 12 / 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

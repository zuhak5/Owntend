import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations_ext.dart';

/// WP-009 (F-017): neutral weather-presentation helpers. They previously
/// lived in the dashboard feature while the settings feature consumed them,
/// forming one side of a settings↔dashboard import cycle.
IconData weatherIcon(int code) {
  return switch (code) {
    0 => Symbols.sunny_rounded,
    1 || 2 || 3 => Symbols.partly_cloudy_day_rounded,
    45 || 48 => Symbols.foggy_rounded,
    51 || 53 || 55 || 56 || 57 => Symbols.rainy_light_rounded,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => Symbols.rainy_rounded,
    71 || 73 || 75 || 77 || 85 || 86 => Symbols.weather_snowy_rounded,
    95 || 96 || 99 => Symbols.thunderstorm_rounded,
    _ => Symbols.cloud_rounded,
  };
}

String localizedWeatherSummary(BuildContext context, int code) {
  return switch (code) {
    0 => context.l10n.clearWeather,
    1 || 2 => context.l10n.partlyCloudy,
    3 => context.l10n.cloudy,
    45 || 48 => context.l10n.fog,
    51 || 53 || 55 || 56 || 57 => context.l10n.drizzle,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => context.l10n.rain,
    71 || 73 || 75 || 77 || 85 || 86 => context.l10n.snow,
    95 || 96 || 99 => context.l10n.storms,
    _ => context.l10n.weather,
  };
}

import 'package:flutter/material.dart';
import 'package:owntend/src/ui/app_theme.dart';

ThemeData testLightTheme() => _withoutInkSparkle(OwntendTheme.light());

ThemeData testDarkTheme() => _withoutInkSparkle(OwntendTheme.dark());

ThemeData testTheme(ThemeData theme) => _withoutInkSparkle(theme);

ThemeData _withoutInkSparkle(ThemeData theme) {
  return theme.copyWith(splashFactory: NoSplash.splashFactory);
}

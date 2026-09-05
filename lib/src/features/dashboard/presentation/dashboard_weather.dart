part of 'dashboard_presentation.dart';

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.location,
    required this.capability,
    required this.localNow,
    required this.isDark,
    required this.onToggleTheme,
    required this.onCapabilityAction,
  });

  final WeatherSnapshot? weather;
  final HomeLocation? location;
  final WeatherAreaCapabilitySnapshot? capability;
  final DateTime localNow;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback? onCapabilityAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = weather;
    final day = isLocalDaytime(localNow);
    final usesCurrentLocation =
        capability?.mode == WeatherAreaMode.device &&
        capability?.effectiveState == EffectiveCapabilityState.active;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.18),
            scheme.secondaryContainer.withValues(alpha: 0.45),
            scheme.surfaceContainerLowest,
          ],
          stops: const [0, 0.58, 1],
        ),
        borderRadius: BorderRadius.circular(HkRadii.xl),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(
            end: -12,
            top: -18,
            child: Icon(
              current == null
                  ? Symbols.cloud_rounded
                  : weatherIcon(current.weatherCode),
              size: 96,
              color: scheme.primary.withValues(alpha: 0.055),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(HkSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current == null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _WeatherIconBadge(icon: Symbols.location_on_rounded),
                      const SizedBox(width: HkSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location == null
                                  ? context.l10n.weatherNotSet
                                  : context.l10n.weatherUnavailable,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: HkSpacing.space2),
                            Text(
                              location == null
                                  ? context.l10n.addHomeLocationInSettings
                                  : context
                                        .l10n
                                        .weatherWillUpdateWhenConnectionReturns,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      _WeatherThemeButton(
                        daytime: day,
                        isDark: isDark,
                        onPressed: onToggleTheme,
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final textScale =
                              MediaQuery.textScalerOf(context).scale(10) / 10;
                          final compactHeader =
                              constraints.maxWidth < 300 || textScale > 1.3;
                          final gap = compactHeader
                              ? HkSpacing.xs
                              : HkSpacing.sm;
                          final temperatureWidth = compactHeader ? 46.0 : 58.0;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _shortWeatherLocationLabel(
                                              context,
                                              current.location.label,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        if (usesCurrentLocation) ...[
                                          const SizedBox(
                                            width: HkSpacing.space6,
                                          ),
                                          const _WeatherCurrentLocationBadge(),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: HkSpacing.space2),
                                    Text(
                                      '${localizedWeatherSummary(context, current.weatherCode)} · ${context.l10n.updatedTime(formatShortTime(context, current.updatedAt))}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: gap),
                              _WeatherThemeButton(
                                daytime: day,
                                isDark: isDark,
                                onPressed: onToggleTheme,
                              ),
                              SizedBox(width: gap),
                              SizedBox(
                                width: temperatureWidth,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    '${current.temperature.round()}°C',
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w800,
                                          height: 1,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: HkSpacing.xs),
                      WeatherDetailChips(weather: current),
                    ],
                  ),
                if (capability != null && !usesCurrentLocation) ...[
                  const SizedBox(height: HkSpacing.xs),
                  _WeatherCapabilityStatus(
                    capability: capability!,
                    onAction: onCapabilityAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherCurrentLocationBadge extends StatelessWidget {
  const _WeatherCurrentLocationBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.permissionUsingCurrentLocation,
      child: Semantics(
        container: true,
        label: context.l10n.permissionUsingCurrentLocation,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 3, 7, 3),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(HkRadii.full),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.my_location_rounded,
                  size: 12,
                  color: scheme.primary,
                ),
                const SizedBox(width: HkSpacing.space4),
                Text(
                  context.l10n.weatherCurrentLocationShort,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherCapabilityStatus extends StatelessWidget {
  const _WeatherCapabilityStatus({
    required this.capability,
    required this.onAction,
  });

  final WeatherAreaCapabilitySnapshot capability;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isManual = capability.mode == WeatherAreaMode.manual;
    final isDeviceActive =
        capability.mode == WeatherAreaMode.device &&
        capability.effectiveState == EffectiveCapabilityState.active;
    final label = isManual && capability.selectedArea != null
        ? context.l10n.permissionSelectedArea(capability.selectedArea!.label)
        : isDeviceActive
        ? context.l10n.permissionUsingCurrentLocation
        : capability.locationServiceEnabled == false
        ? context.l10n.locationServicesAreOff
        : capability.isConfigured
        ? context.l10n.permissionLocationAccessRequired
        : context.l10n.weatherNotSet;
    final showAction = !isDeviceActive;
    final actionLabel = isManual
        ? context.l10n.change
        : capability.locationServiceEnabled == false
        ? context.l10n.turnOnLocationServices
        : context.l10n.configure;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        children: [
          Icon(
            isManual
                ? Symbols.location_city_rounded
                : isDeviceActive
                ? Symbols.my_location_rounded
                : Symbols.location_off_rounded,
            size: 18,
            color: isManual || isDeviceActive ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              label,
              key: const ValueKey('dashboard-weather-capability-status'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (showAction)
            SizedBox(
              height: 48,
              child: TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Symbols.settings_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeatherThemeButton extends StatelessWidget {
  const _WeatherThemeButton({
    required this.daytime,
    required this.isDark,
    required this.onPressed,
  });

  final bool daytime;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = isDark
        ? context.l10n.switchToLightMode
        : context.l10n.switchToDarkMode;
    return Tooltip(
      message: message,
      child: Semantics(
        button: true,
        label: message,
        child: SizedBox.square(
          dimension: 48,
          child: IconButton(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerLowest.withValues(
                alpha: 0.86,
              ),
              foregroundColor: daytime ? scheme.tertiary : scheme.primary,
              shape: const CircleBorder(),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.12)),
            ),
            icon: Icon(
              daytime ? Symbols.wb_sunny_rounded : Symbols.dark_mode_rounded,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class WeatherDetailChips extends StatelessWidget {
  const WeatherDetailChips({required this.weather, super.key});

  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final compact = constraints.maxWidth < 340 || textScale > 1.3;
        final showIcons = constraints.maxWidth >= 320 && textScale <= 1.3;
        final gap = compact ? HkSpacing.space4 : HkSpacing.space6;
        return Row(
          children: [
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.thermostat_rounded,
                label: context.l10n.feels,
                value: '${weather.apparentTemperature.round()}°C',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.water_drop_rounded,
                label: context.l10n.humidity,
                value: '${weather.humidity}%',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.air_rounded,
                label: context.l10n.wind,
                value: '${weather.windSpeed.round()} km/h',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeatherIconBadge extends StatelessWidget {
  const _WeatherIconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.82),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: scheme.primary, size: 20),
    );
  }
}

class _WeatherDetailChip extends StatelessWidget {
  const _WeatherDetailChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.compact,
    required this.showIcon,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool compact;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 32 : 34),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? HkSpacing.space4 : HkSpacing.xs,
        vertical: HkSpacing.space6,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: showIcon
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: compact ? 13 : 15, color: scheme.primary),
                    SizedBox(width: compact ? 3 : HkSpacing.space4),
                    _WeatherDetailText(
                      label: label,
                      value: value,
                      compact: compact,
                    ),
                  ],
                )
              : _WeatherDetailText(
                  label: label,
                  value: value,
                  compact: compact,
                ),
        ),
      ),
    );
  }
}

class _WeatherDetailText extends StatelessWidget {
  const _WeatherDetailText({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final formattedValue = isRtl ? '\u2066$value\u2069' : value;
    return Text(
      '$label $formattedValue',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        fontSize: compact ? 10.5 : null,
      ),
    );
  }
}

Future<void> syncProfileIfEnabled(WidgetRef ref) async {
  try {
    final sync = ref.read(cloudSyncRepositoryProvider);
    final status = await sync.status();
    if (status.enabled) {
      await sync.syncNow();
    }
  } catch (_) {
    // Profile sync is best-effort; visible sync status surfaces failures.
  }
}

String _shortWeatherLocationLabel(BuildContext context, String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return context.l10n.home;
  }
  final firstPart = trimmed.split(RegExp(r'[,\n]')).first.trim();
  final withoutDistrict = firstPart.replaceFirst(
    RegExp(r'\s+District$', caseSensitive: false),
    '',
  );
  if (withoutDistrict.trim().isNotEmpty) {
    return withoutDistrict.trim();
  }
  return firstPart.isEmpty ? trimmed : firstPart;
}

String _greetingName(
  BuildContext context,
  AppProfile profile,
  AuthSession? session,
) {
  for (final candidate in [
    profile.nickname,
    session?.fullName,
    session?.name,
    _emailUsername(session?.email),
    context.l10n.there,
  ]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return context.l10n.there;
}

String? _emailUsername(String? email) {
  final trimmed = email?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final atIndex = trimmed.indexOf('@');
  if (atIndex <= 0) {
    return trimmed;
  }
  return trimmed.substring(0, atIndex);
}

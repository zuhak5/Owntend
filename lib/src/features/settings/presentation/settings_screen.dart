import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import '../../maintenance/presentation/task_actions.dart';
import '../../../ui/widgets/location_picker_sheet.dart';
import '../../monetization/monetization.dart';
import '../../../ui/widgets/weather_presentation.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(
          ref
              .read(permissionEducationControllerProvider.notifier)
              .refreshCapabilities(),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(permissionEducationControllerProvider.notifier)
            .handleAppResume(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = ref.watch(appConfigProvider);
    final location = ref.watch(homeLocationProvider).value;
    final weather = ref.watch(weatherProvider).value;
    final startupTheme = ref.watch(startupThemeSettingsProvider);
    final themePreference =
        ref.watch(themePreferenceProvider).value ?? startupTheme.preference;
    final localePreference =
        ref.watch(appLocalePreferenceProvider).value ??
        AppLocalePreference(
          language: supportedDeviceLanguage(
            WidgetsBinding.instance.platformDispatcher.locale,
          ),
          isExplicit: false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
    final notificationPreferences =
        ref.watch(notificationPreferencesProvider).value ??
        const NotificationPreferences();
    final capabilitySetup = ref
        .watch(permissionEducationControllerProvider)
        .setupSnapshot;
    final consent = ref.watch(consentSnapshotProvider).value;
    final reminderHours = {
      ...[7, 8, 9, 10, 12, 18],
      notificationPreferences.reminderHour,
    }.toList()..sort();
    final digestHours = {
      ...[8, 12, 17, 18, 20],
      notificationPreferences.digestHour,
    }.toList()..sort();
    final snoozeOptions = {
      30,
      60,
      180,
      24 * 60,
      notificationPreferences.defaultSnoozeMinutes,
    }.toList()..sort();
    final supportsMobileAdDebugging = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Scrollbar(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 112),
              children: [
                const HkNativeAdCard(placement: 'settings'),
                hk_ui.PremiumCard(
                  padding: const EdgeInsets.all(HkSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsCardHeader(
                        icon: Symbols.contrast_rounded,
                        title: context.l10n.appearance,
                      ),
                      const SizedBox(height: HkSpacing.sm),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final textScaler = MediaQuery.textScalerOf(context);
                          final isCompactLayout =
                              constraints.maxWidth < 360 ||
                              textScaler.scale(1) > 1.2;
                          final useShortLabel =
                              constraints.maxWidth < 320 ||
                              (constraints.maxWidth < 420 &&
                                  textScaler.scale(1) > 1.4);
                          return SizedBox(
                            width: double.infinity,
                            child: MediaQuery.withClampedTextScaling(
                              maxScaleFactor: isCompactLayout ? 1.15 : 1.3,
                              child: SegmentedButton<ThemePreference>(
                                showSelectedIcon: false,
                                style: isCompactLayout
                                    ? SegmentedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 6,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      )
                                    : null,
                                segments: [
                                  ButtonSegment(
                                    value: ThemePreference.light,
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        context.l10n.light,
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                    icon: isCompactLayout
                                        ? null
                                        : const Icon(
                                            Symbols.light_mode_rounded,
                                          ),
                                  ),
                                  ButtonSegment(
                                    value: ThemePreference.dark,
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        context.l10n.dark,
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                    icon: isCompactLayout
                                        ? null
                                        : const Icon(Symbols.dark_mode_rounded),
                                  ),
                                  ButtonSegment(
                                    value: ThemePreference.system,
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        useShortLabel
                                            ? context.l10n.auto
                                            : context.l10n.automatic,
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                    icon: isCompactLayout
                                        ? null
                                        : const Icon(Symbols.schedule_rounded),
                                  ),
                                ],
                                selected: {themePreference},
                                onSelectionChanged: (selection) {
                                  final preference = selection.single;
                                  _setThemePreference(context, ref, preference);
                                },
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: HkSpacing.space6),
                      Text(
                        themePreference == ThemePreference.system
                            ? context
                                  .l10n
                                  .automaticUsesYourLocalTimeLightFrom6AmTo6PmDarkOvernight
                            : context
                                  .l10n
                                  .manualSelectionStaysActiveUntilYouChooseAnotherMode,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HkSpacing.sm),
                hk_ui.LanguageSelectorDropdown(
                  selectorKey: const ValueKey('settings-language-selector'),
                  hitTargetKey: const ValueKey(
                    'settings-language-selector-hit-target',
                  ),
                  language: localePreference.language,
                  chevronSize: 20,
                  onChanged: (selection) =>
                      _setAppLanguage(context, ref, selection),
                  triggerBuilder: (context, label, isOpen, chevron) {
                    final scheme = Theme.of(context).colorScheme;
                    return hk_ui.PremiumCard(
                      padding: EdgeInsets.zero,
                      borderColor: isOpen
                          ? scheme.primary.withValues(alpha: 0.65)
                          : null,
                      backgroundColor: isOpen
                          ? Color.alphaBlend(
                              scheme.primary.withValues(alpha: 0.035),
                              scheme.surfaceContainerLowest,
                            )
                          : null,
                      child: ConstrainedBox(
                        key: const ValueKey('settings-language-row'),
                        constraints: const BoxConstraints(minHeight: 72),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SettingsRowGrid.contentInset,
                            vertical: HkSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              const _SettingsTileIcon(
                                icon: Symbols.language_rounded,
                              ),
                              const SizedBox(width: HkSpacing.sm),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  context.l10n.language,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: HkSpacing.sm),
                              Flexible(
                                flex: 2,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: HkSpacing.space4),
                                    chevron,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: HkSpacing.sm),
                if (consent?.privacyOptionsRequired ?? false) ...[
                  hk_ui.PremiumCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SettingsRowGrid.contentInset,
                      vertical: HkSpacing.xs,
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      minLeadingWidth: SettingsRowGrid.leadingWidth,
                      horizontalTitleGap: SettingsRowGrid.iconToTextGap,
                      leading: const _SettingsTileIcon(
                        icon: Symbols.privacy_tip_rounded,
                      ),
                      title: Text(context.l10n.privacyChoices),
                      subtitle: Text(context.l10n.privacyChoicesSubtitle),
                      trailing: Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Symbols.chevron_left_rounded
                            : Symbols.chevron_right_rounded,
                      ),
                      onTap: () =>
                          ref.read(consentServiceProvider).showPrivacyOptions(),
                    ),
                  ),
                  const SizedBox(height: HkSpacing.sm),
                ],
                if (appConfig.environment != AppEnvironment.prod &&
                    supportsMobileAdDebugging) ...[
                  hk_ui.PremiumCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SettingsRowGrid.contentInset,
                      vertical: HkSpacing.xs,
                    ),
                    child: ListTile(
                      key: const ValueKey('settings-ad-inspector'),
                      contentPadding: EdgeInsets.zero,
                      minLeadingWidth: SettingsRowGrid.leadingWidth,
                      horizontalTitleGap: SettingsRowGrid.iconToTextGap,
                      leading: const _SettingsTileIcon(
                        icon: Symbols.bug_report_rounded,
                      ),
                      title: Text(context.l10n.adInspector),
                      subtitle: Text(context.l10n.adInspectorSubtitle),
                      trailing: Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Symbols.chevron_left_rounded
                            : Symbols.chevron_right_rounded,
                      ),
                      onTap: () => _openAdInspector(context, ref),
                    ),
                  ),
                  const SizedBox(height: HkSpacing.sm),
                ],
                hk_ui.PremiumCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SettingsRowGrid.contentInset,
                    vertical: HkSpacing.xs,
                  ),
                  child: ListTile(
                    key: const ValueKey('settings-weather-row'),
                    contentPadding: EdgeInsets.zero,
                    minLeadingWidth: SettingsRowGrid.leadingWidth,
                    horizontalTitleGap: SettingsRowGrid.iconToTextGap,
                    leading: _SettingsTileIcon(
                      icon: weather == null
                          ? Symbols.location_on_rounded
                          : weatherIcon(weather.weatherCode),
                    ),
                    title: Text(context.l10n.weatherLocation),
                    subtitle: Text(
                      weather == null
                          ? context.l10n.setACityZipOrCurrentDeviceLocation
                          : '${location?.label ?? context.l10n.home}\n${localizedWeatherSummary(context, weather.weatherCode)} · ${formatInteger(context, weather.temperature.round())}°C',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: context.l10n.searchLocation,
                          onPressed: () => _searchLocation(context, ref),
                          icon: const Icon(Symbols.search_rounded),
                        ),
                        IconButton(
                          tooltip: context.l10n.useDeviceLocation,
                          onPressed: () => _useDeviceLocation(context, ref),
                          icon: const Icon(Symbols.my_location_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: HkSpacing.sm),
                hk_ui.PremiumCard(
                  padding: const EdgeInsets.all(HkSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsCardHeader(
                        icon: Symbols.notifications_active_rounded,
                        title: context.l10n.notifications,
                      ),
                      const SizedBox(height: HkSpacing.md),
                      _SettingsSubsectionLabel(label: context.l10n.permissions),
                      const SizedBox(height: HkSpacing.xs),
                      _SettingsPanel(
                        child: Column(
                          children: [
                            if (capabilitySetup == null)
                              const Padding(
                                padding: EdgeInsets.all(HkSpacing.sm),
                                child: LinearProgressIndicator(),
                              )
                            else ...[
                              _NotificationStatusRow(
                                icon: Symbols.notifications_rounded,
                                label: context.l10n.deviceReminders,
                                value: _effectiveCapabilityLabel(
                                  context,
                                  capabilitySetup
                                      .notifications
                                      .deviceReminderState,
                                ),
                                good:
                                    capabilitySetup
                                        .notifications
                                        .deviceReminderState ==
                                    EffectiveCapabilityState.active,
                              ),
                              _NotificationStatusRow(
                                icon: Symbols.inbox_rounded,
                                label: context.l10n.inAppInbox,
                                value: _effectiveCapabilityLabel(
                                  context,
                                  capabilitySetup.notifications.inboxState,
                                ),
                                good:
                                    capabilitySetup.notifications.inboxState ==
                                    EffectiveCapabilityState.active,
                              ),
                              _NotificationStatusRow(
                                icon: Symbols.rainy_rounded,
                                label: context.l10n.weatherAlerts,
                                value: _effectiveCapabilityLabel(
                                  context,
                                  capabilitySetup
                                      .notifications
                                      .weatherAlertState,
                                ),
                                good:
                                    capabilitySetup
                                        .notifications
                                        .weatherAlertState ==
                                    EffectiveCapabilityState.active,
                              ),
                            ],
                            const Divider(height: HkSpacing.md),
                            ListTile(
                              key: const ValueKey(
                                'settings-permission-education',
                              ),
                              contentPadding: EdgeInsets.zero,
                              leading: const _SettingsTileIcon(
                                icon: Symbols.health_and_safety_rounded,
                              ),
                              title: Text(
                                context.l10n.permissionSetup,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                context.l10n.permissionSetupSubtitle,
                              ),
                              trailing: Icon(
                                Directionality.of(context) == TextDirection.rtl
                                    ? Symbols.chevron_left_rounded
                                    : Symbols.chevron_right_rounded,
                              ),
                              onTap: () => _openPermissionSetup(context, ref),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: HkSpacing.md),
                      _SettingsSubsectionLabel(label: context.l10n.preferences),
                      const SizedBox(height: HkSpacing.xs),
                      _SettingsPanel(
                        child: Column(
                          children: [
                            SwitchListTile(
                              key: const ValueKey('settings-alerts-row'),
                              contentPadding: EdgeInsets.zero,
                              secondary: const _SettingsPlainIcon(
                                icon: Icons.notifications_active_outlined,
                              ),
                              title: Text(context.l10n.owntendAlerts),
                              subtitle: Text(
                                context.l10n.owntendAlertsDescription,
                              ),
                              value: notificationPreferences.enabled,
                              onChanged: (value) =>
                                  _saveNotificationPreferences(
                                    context,
                                    ref,
                                    notificationPreferences,
                                    notificationPreferences.copyWith(
                                      enabled: value,
                                    ),
                                  ),
                            ),
                            const _SettingsPreferenceDivider(),
                            if (capabilitySetup != null &&
                                notificationPreferences.allowsLocalReminders &&
                                capabilitySetup
                                        .notifications
                                        .deviceReminderState !=
                                    EffectiveCapabilityState.active)
                              _EffectiveCapabilityPreferenceTile(
                                key: const ValueKey(
                                  'device-reminders-recovery',
                                ),
                                icon: Symbols.alarm_rounded,
                                title: context.l10n.deviceReminders,
                                subtitle: context
                                    .l10n
                                    .scheduledAndroidReminderDelivery,
                                state: capabilitySetup
                                    .notifications
                                    .deviceReminderState,
                                onFix: () =>
                                    _enableDeviceReminders(context, ref),
                              )
                            else
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: const _SettingsPlainIcon(
                                  icon: Symbols.alarm_rounded,
                                ),
                                title: Text(context.l10n.deviceReminders),
                                subtitle: Text(
                                  context.l10n.scheduledAndroidReminderDelivery,
                                ),
                                value:
                                    notificationPreferences.enabled &&
                                    notificationPreferences.localReminders,
                                onChanged: notificationPreferences.enabled
                                    ? (value) => value
                                          ? _enableDeviceReminders(context, ref)
                                          : _saveNotificationPreferences(
                                              context,
                                              ref,
                                              notificationPreferences,
                                              notificationPreferences.copyWith(
                                                localReminders: false,
                                              ),
                                            )
                                    : null,
                              ),
                            const _SettingsPreferenceDivider(),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const _SettingsPlainIcon(
                                icon: Symbols.inbox_rounded,
                              ),
                              title: Text(context.l10n.inAppInbox),
                              subtitle: Text(
                                context.l10n.unreadTaskWeatherAndDigestUpdates,
                              ),
                              value:
                                  notificationPreferences.enabled &&
                                  notificationPreferences.inAppInbox,
                              onChanged: notificationPreferences.enabled
                                  ? (value) => _saveNotificationPreferences(
                                      context,
                                      ref,
                                      notificationPreferences,
                                      notificationPreferences.copyWith(
                                        inAppInbox: value,
                                      ),
                                    )
                                  : null,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const _SettingsPlainIcon(
                                icon: Symbols.rainy_rounded,
                              ),
                              title: Text(context.l10n.weatherAlerts),
                              subtitle: Text(
                                context.l10n.weatherAlertsInboxDescription,
                              ),
                              value:
                                  notificationPreferences.enabled &&
                                  notificationPreferences.weatherAlerts,
                              onChanged: notificationPreferences.enabled
                                  ? (value) => _saveNotificationPreferences(
                                      context,
                                      ref,
                                      notificationPreferences,
                                      notificationPreferences.copyWith(
                                        weatherAlerts: value,
                                      ),
                                    )
                                  : null,
                            ),
                            const _SettingsPreferenceDivider(),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const _SettingsPlainIcon(
                                icon: Symbols.do_not_disturb_on_rounded,
                              ),
                              title: Text(context.l10n.quietHours),
                              subtitle: Text(
                                '${_minutesLabel(context, notificationPreferences.quietHoursStartMinutes)} - ${_minutesLabel(context, notificationPreferences.quietHoursEndMinutes)}',
                              ),
                              value:
                                  notificationPreferences.enabled &&
                                  notificationPreferences.quietHoursEnabled,
                              onChanged: notificationPreferences.enabled
                                  ? (value) => _saveNotificationPreferences(
                                      context,
                                      ref,
                                      notificationPreferences,
                                      notificationPreferences.copyWith(
                                        quietHoursEnabled: value,
                                      ),
                                    )
                                  : null,
                            ),
                            if (notificationPreferences.quietHoursEnabled) ...[
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: HkSpacing.sm,
                                ),
                                child: Column(
                                  children: [
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const _SettingsPlainIcon(
                                        icon: Symbols.bedtime_rounded,
                                      ),
                                      title: Text(context.l10n.quietHoursStart),
                                      subtitle: Text(
                                        _minutesLabel(
                                          context,
                                          notificationPreferences
                                              .quietHoursStartMinutes,
                                        ),
                                      ),
                                      trailing: Icon(
                                        Directionality.of(context) ==
                                                TextDirection.rtl
                                            ? Symbols.chevron_left_rounded
                                            : Symbols.chevron_right_rounded,
                                      ),
                                      onTap: notificationPreferences.enabled
                                          ? () => _pickQuietHour(
                                              context,
                                              ref,
                                              notificationPreferences,
                                              start: true,
                                            )
                                          : null,
                                    ),
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const _SettingsPlainIcon(
                                        icon: Symbols.wb_sunny_rounded,
                                      ),
                                      title: Text(context.l10n.quietHoursEnd),
                                      subtitle: Text(
                                        _minutesLabel(
                                          context,
                                          notificationPreferences
                                              .quietHoursEndMinutes,
                                        ),
                                      ),
                                      trailing: Icon(
                                        Directionality.of(context) ==
                                                TextDirection.rtl
                                            ? Symbols.chevron_left_rounded
                                            : Symbols.chevron_right_rounded,
                                      ),
                                      onTap: notificationPreferences.enabled
                                          ? () => _pickQuietHour(
                                              context,
                                              ref,
                                              notificationPreferences,
                                              start: false,
                                            )
                                          : null,
                                    ),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      secondary: const _SettingsPlainIcon(
                                        icon: Symbols.priority_high_rounded,
                                      ),
                                      title: Text(
                                        context.l10n.criticalRemindersBypass,
                                      ),
                                      subtitle: Text(
                                        context
                                            .l10n
                                            .criticalTasksCanStillAlertDuringQuietHours,
                                      ),
                                      value:
                                          notificationPreferences.enabled &&
                                          notificationPreferences
                                              .criticalBypassQuietHours,
                                      onChanged: notificationPreferences.enabled
                                          ? (
                                              value,
                                            ) => _saveNotificationPreferences(
                                              context,
                                              ref,
                                              notificationPreferences,
                                              notificationPreferences.copyWith(
                                                criticalBypassQuietHours: value,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const _SettingsPlainIcon(
                                icon: Symbols.privacy_tip_rounded,
                              ),
                              title: Text(context.l10n.hideLockScreenDetails),
                              subtitle: Text(
                                context
                                    .l10n
                                    .showGenericReminderTextOutsideTheApp,
                              ),
                              value:
                                  notificationPreferences.enabled &&
                                  notificationPreferences.privacyMode,
                              onChanged: notificationPreferences.enabled
                                  ? (value) => _saveNotificationPreferences(
                                      context,
                                      ref,
                                      notificationPreferences,
                                      notificationPreferences.copyWith(
                                        privacyMode: value,
                                      ),
                                    )
                                  : null,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const _SettingsPlainIcon(
                                icon: Symbols.summarize_rounded,
                              ),
                              title: Text(context.l10n.dailyDigest),
                              subtitle: Text(
                                context.l10n.groupedReminderSummary,
                              ),
                              value:
                                  notificationPreferences.enabled &&
                                  notificationPreferences.dailyDigest,
                              onChanged: notificationPreferences.enabled
                                  ? (value) => _saveNotificationPreferences(
                                      context,
                                      ref,
                                      notificationPreferences,
                                      notificationPreferences.copyWith(
                                        dailyDigest: value,
                                      ),
                                    )
                                  : null,
                            ),
                            const _SettingsPreferenceDivider(),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const _SettingsPlainIcon(
                                icon: Symbols.snooze_rounded,
                              ),
                              title: Text(context.l10n.defaultSnooze),
                              subtitle: Text(
                                durationLabel(
                                  context,
                                  Duration(
                                    minutes: notificationPreferences
                                        .defaultSnoozeMinutes,
                                  ),
                                ),
                              ),
                              trailing: DropdownButton<int>(
                                value: notificationPreferences
                                    .defaultSnoozeMinutes,
                                items: [
                                  for (final minutes in snoozeOptions)
                                    DropdownMenuItem(
                                      value: minutes,
                                      child: Text(
                                        durationLabel(
                                          context,
                                          Duration(minutes: minutes),
                                        ),
                                      ),
                                    ),
                                ],
                                onChanged: notificationPreferences.enabled
                                    ? (minutes) {
                                        if (minutes == null) {
                                          return;
                                        }
                                        _saveNotificationPreferences(
                                          context,
                                          ref,
                                          notificationPreferences,
                                          notificationPreferences.copyWith(
                                            defaultSnoozeMinutes: minutes,
                                          ),
                                        );
                                      }
                                    : null,
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const _SettingsPlainIcon(
                                icon: Symbols.notifications_rounded,
                              ),
                              title: Text(context.l10n.maxRemindersPerDay),
                              subtitle: Text(
                                context.l10n.reminderCountLabel(
                                  notificationPreferences.maxRemindersPerDay,
                                ),
                              ),
                              trailing: DropdownButton<int>(
                                value:
                                    notificationPreferences.maxRemindersPerDay,
                                items: [
                                  for (final count in const [
                                    2,
                                    4,
                                    6,
                                    8,
                                    12,
                                    24,
                                  ])
                                    DropdownMenuItem(
                                      value: count,
                                      child: Text(
                                        formatInteger(context, count),
                                      ),
                                    ),
                                ],
                                onChanged: notificationPreferences.enabled
                                    ? (count) {
                                        if (count == null) {
                                          return;
                                        }
                                        _saveNotificationPreferences(
                                          context,
                                          ref,
                                          notificationPreferences,
                                          notificationPreferences.copyWith(
                                            maxRemindersPerDay: count,
                                          ),
                                        );
                                      }
                                    : null,
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const _SettingsPlainIcon(
                                icon: Symbols.schedule_rounded,
                              ),
                              title: Text(context.l10n.reminderTime),
                              subtitle: Text(
                                hourLabel(
                                  context,
                                  notificationPreferences.reminderHour,
                                ),
                              ),
                              trailing: DropdownButton<int>(
                                value: notificationPreferences.reminderHour,
                                items: [
                                  for (final hour in reminderHours)
                                    DropdownMenuItem(
                                      value: hour,
                                      child: Text(hourLabel(context, hour)),
                                    ),
                                ],
                                onChanged: notificationPreferences.enabled
                                    ? (hour) {
                                        if (hour == null) {
                                          return;
                                        }
                                        _saveNotificationPreferences(
                                          context,
                                          ref,
                                          notificationPreferences,
                                          notificationPreferences.copyWith(
                                            reminderHour: hour,
                                          ),
                                        );
                                      }
                                    : null,
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const _SettingsPlainIcon(
                                icon: Symbols.event_note_rounded,
                              ),
                              title: Text(context.l10n.digestTime),
                              subtitle: Text(
                                hourLabel(
                                  context,
                                  notificationPreferences.digestHour,
                                ),
                              ),
                              trailing: DropdownButton<int>(
                                value: notificationPreferences.digestHour,
                                items: [
                                  for (final hour in digestHours)
                                    DropdownMenuItem(
                                      value: hour,
                                      child: Text(hourLabel(context, hour)),
                                    ),
                                ],
                                onChanged: notificationPreferences.enabled
                                    ? (hour) {
                                        if (hour == null) {
                                          return;
                                        }
                                        _saveNotificationPreferences(
                                          context,
                                          ref,
                                          notificationPreferences,
                                          notificationPreferences.copyWith(
                                            digestHour: hour,
                                          ),
                                        );
                                      }
                                    : null,
                              ),
                            ),
                            _ReminderSettingsActions(
                              onSendTest: () =>
                                  _sendTestNotification(context, ref),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setThemePreference(
    BuildContext context,
    WidgetRef ref,
    ThemePreference preference,
  ) async {
    try {
      final repository = ref.read(settingsRepositoryProvider);
      await repository.setThemePreference(preference);
      await repository.setTimeOfDayThemeEnabled(
        preference == ThemePreference.system,
      );
    } catch (error) {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(
          failureMessage(context, error, fallback: AppFailureCode.themeUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }

  Future<void> _openPermissionSetup(BuildContext context, WidgetRef ref) async {
    await context.push('/permissions/setup');
  }

  Future<void> _setAppLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLanguage language,
  ) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setAppLocalePreference(language);
    } on Object {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(context.l10n.languageUpdateFailedPleaseTryAgain),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }

  Future<void> _searchLocation(BuildContext context, WidgetRef ref) async {
    final location = await showEditorModal<HomeLocation>(
      context,
      builder: (context) => const LocationPickerSheet(),
    );
    if (location == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await ref.read(settingsRepositoryProvider).setHomeLocation(location);
    await ref.read(weatherRepositoryProvider).refreshWeather();
    await refreshNotificationSchedules(ref);
    await ref
        .read(permissionEducationControllerProvider.notifier)
        .refreshCapabilities();
    if (!context.mounted) {
      return;
    }
    ref.invalidate(homeLocationProvider);
    ref.invalidate(weatherProvider);
  }

  Future<void> _useDeviceLocation(BuildContext context, WidgetRef ref) async {
    try {
      final controller = ref.read(
        permissionEducationControllerProvider.notifier,
      );
      await controller.refreshCapabilities();
      await controller.useCurrentLocation();
      if (!context.mounted) {
        return;
      }
      final location =
          controller.currentState.setupSnapshot?.weather.selectedArea;
      if (location == null || location.source.toLowerCase() != 'device') {
        hk_ui.showToast(
          context,
          content: Text(context.l10n.deviceLocationIsUnavailable),
          severity: hk_ui.HkToastSeverity.error,
        );
        return;
      }
      await ref.read(weatherRepositoryProvider).refreshWeather();
      await refreshNotificationSchedules(ref);
      if (!context.mounted) {
        return;
      }
      ref.invalidate(homeLocationProvider);
      ref.invalidate(weatherProvider);
      hk_ui.showToast(
        context,
        content: Text(context.l10n.weatherLocationUpdated),
      );
    } catch (error) {
      if (context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(
            failureMessage(
              context,
              error,
              fallback: AppFailureCode.locationUpdate,
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    }
  }

  Future<void> _openAdInspector(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(owntendAdsProvider).openAdInspector();
    if (!context.mounted) return;
    switch (result) {
      case AdInspectorOpenResult.opened:
        return;
      case AdInspectorOpenResult.unavailable:
        hk_ui.showToast(
          context,
          content: Text(context.l10n.adInspectorUnavailable),
        );
      case AdInspectorOpenResult.failed:
        hk_ui.showToast(
          context,
          content: Text(context.l10n.adInspectorOpenFailed),
          severity: hk_ui.HkToastSeverity.error,
        );
    }
  }

  Future<void> _pickQuietHour(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences preferences, {
    required bool start,
  }) async {
    final initialMinutes = start
        ? preferences.quietHoursStartMinutes
        : preferences.quietHoursEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDayFromMinutes(initialMinutes),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    final minutes = _minutesFromTimeOfDay(picked);
    await _saveNotificationPreferences(
      context,
      ref,
      preferences,
      start
          ? preferences.copyWith(quietHoursStartMinutes: minutes)
          : preferences.copyWith(quietHoursEndMinutes: minutes),
    );
  }

  Future<void> _saveNotificationPreferences(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences baseline,
    NotificationPreferences preferences,
  ) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .mergeNotificationPreferences(
            baseline: baseline,
            desired: preferences,
          );
      ref.invalidate(notificationPreferencesProvider);
      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.initialize();
      await scheduler.refreshSchedules();
      ref.invalidate(notificationPermissionStateProvider);
      await ref
          .read(permissionEducationControllerProvider.notifier)
          .refreshCapabilities();
      if (!context.mounted) {
        return;
      }
      hk_ui.showToast(
        context,
        content: Text(context.l10n.notificationSettingsUpdated),
      );
    } catch (error) {
      if (context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(
            failureMessage(
              context,
              error,
              fallback: AppFailureCode.notificationSetup,
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    }
  }

  Future<void> _enableDeviceReminders(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final controller = ref.read(
        permissionEducationControllerProvider.notifier,
      );
      await controller.refreshCapabilities();
      await controller.enableNotifications();
      ref.invalidate(notificationPreferencesProvider);
      ref.invalidate(notificationPermissionStateProvider);
      if (!context.mounted) return;
      final effective = controller
          .currentState
          .setupSnapshot
          ?.notifications
          .deviceReminderState;
      if (effective == EffectiveCapabilityState.active) {
        hk_ui.showToast(
          context,
          content: Text(context.l10n.notificationSettingsUpdated),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(
          failureMessage(
            context,
            error,
            fallback: AppFailureCode.notificationSetup,
          ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }

  Future<void> _sendTestNotification(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final allowed = await _ensurePermission(
        context,
        ref,
        kind: AppPermissionKind.notifications,
        title: context.l10n.sendATestReminder,
        message: context.l10n.allowNotificationsForReminders,
      );
      if (!allowed || !context.mounted) return;
      await ref.read(notificationSchedulerProvider).sendTestReminder();
      if (!context.mounted) {
        return;
      }
      ref.invalidate(notificationPermissionStateProvider);
      hk_ui.showToast(
        context,
        content: Text(context.l10n.testReminderScheduled),
      );
    } catch (error) {
      if (context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(
            failureMessage(
              context,
              error,
              fallback: AppFailureCode.testReminder,
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    }
  }

  Future<bool> _ensurePermission(
    BuildContext context,
    WidgetRef ref, {
    required AppPermissionKind kind,
    required String title,
    required String message,
  }) async {
    final coordinator = ref.read(permissionCoordinatorProvider);
    var state = await coordinator.check(kind);
    if (state == AppPermissionState.granted) return true;
    if (!context.mounted) return false;
    if (state == AppPermissionState.serviceDisabled) {
      final open = await _permissionDialog(
        context,
        title: context.l10n.locationServicesAreOff,
        message: context.l10n.turnOnLocationServices,
        action: context.l10n.openSettings,
      );
      if (open) await coordinator.openLocationServiceSettings();
      return false;
    }
    if (state == AppPermissionState.permanentlyDenied ||
        state == AppPermissionState.restricted) {
      final open = await _permissionDialog(
        context,
        title: context.l10n.permissionNeeded,
        message: context.l10n.allowInSystemSettings(message),
        action: context.l10n.openSettings,
      );
      if (open) await coordinator.openAppPermissionSettings();
      return false;
    }
    if (state == AppPermissionState.unavailable) return false;
    final continueRequest = await _permissionDialog(
      context,
      title: title,
      message: message,
      action: context.l10n.continueLabel,
    );
    if (!continueRequest) return false;
    state = await coordinator.request(kind);
    if (state == AppPermissionState.granted) return true;
    if (context.mounted && state == AppPermissionState.permanentlyDenied) {
      final open = await _permissionDialog(
        context,
        title: context.l10n.permissionBlocked,
        message: context.l10n.allowPermissionInSystemSettings,
        action: context.l10n.openSettings,
      );
      if (open) await coordinator.openAppPermissionSettings();
    }
    return false;
  }

  Future<bool> _permissionDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.notNow),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class SettingsRowGrid extends StatelessWidget {
  const SettingsRowGrid({required this.child, super.key});

  static const double contentInset = HkSpacing.space20;
  static const double leadingWidth = 40;
  static const double iconToTextGap = HkSpacing.sm;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListTileTheme(
      data: Theme.of(context).listTileTheme.copyWith(
        minLeadingWidth: leadingWidth,
        horizontalTitleGap: iconToTextGap,
      ),
      child: child,
    );
  }
}

class _SettingsCardHeader extends StatelessWidget {
  const _SettingsCardHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SettingsTileIcon(icon: icon),
        const SizedBox(width: HkSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _SettingsSubsectionLabel extends StatelessWidget {
  const _SettingsSubsectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: HkSpacing.space4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HkRadii.lg),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HkSpacing.space4,
          vertical: HkSpacing.space4,
        ),
        child: SettingsRowGrid(
          child: IconTheme(
            data: IconThemeData(color: scheme.primary),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SettingsTileIcon extends StatelessWidget {
  const _SettingsTileIcon({
    required this.icon,
    this.color,
    this.size = SettingsRowGrid.leadingWidth,
    this.iconSize = 21,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(HkRadii.md),
      ),
      child: Icon(icon, size: iconSize, color: resolvedColor),
    );
  }
}

class _SettingsPlainIcon extends StatelessWidget {
  const _SettingsPlainIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: SettingsRowGrid.leadingWidth,
      child: Center(child: Icon(icon)),
    );
  }
}

class _SettingsPreferenceDivider extends StatelessWidget {
  const _SettingsPreferenceDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: SettingsRowGrid.leadingWidth + SettingsRowGrid.iconToTextGap,
        end: HkSpacing.xs,
      ),
      child: Divider(
        height: HkSpacing.space4,
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: 0.72),
      ),
    );
  }
}

class _ReminderSettingsActions extends StatelessWidget {
  const _ReminderSettingsActions({required this.onSendTest});

  final VoidCallback onSendTest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HkSpacing.xs,
        HkSpacing.xs,
        HkSpacing.xs,
        HkSpacing.space4,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: onSendTest,
          icon: const Icon(Symbols.notification_add_rounded, size: 19),
          label: Text(context.l10n.sendTest, maxLines: 1),
        ),
      ),
    );
  }
}

class _NotificationStatusRow extends StatelessWidget {
  const _NotificationStatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.good,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? HkColors.green : HkColors.tertiary;
    final status = hk_ui.StatusPill(label: value, color: color, compact: true);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final stacked =
            constraints.maxWidth < 276 || textScaler.scale(14) > 17.5;
        final labelRow = Row(
          children: [
            _SettingsTileIcon(icon: icon, color: color, size: 32, iconSize: 18),
            const SizedBox(width: HkSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HkSpacing.xs,
            vertical: HkSpacing.space6,
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    labelRow,
                    const SizedBox(height: HkSpacing.space6),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: status,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: labelRow),
                    const SizedBox(width: HkSpacing.xs),
                    status,
                  ],
                ),
        );
      },
    );
  }
}

class _EffectiveCapabilityPreferenceTile extends StatelessWidget {
  const _EffectiveCapabilityPreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.onFix,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final EffectiveCapabilityState state;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      EffectiveCapabilityState.active => HkColors.green,
      EffectiveCapabilityState.degraded => HkColors.tertiary,
      EffectiveCapabilityState.blocked => scheme.error,
      EffectiveCapabilityState.disabledByUser => scheme.onSurfaceVariant,
      EffectiveCapabilityState.notConfigured => HkColors.tertiary,
      EffectiveCapabilityState.unavailable => scheme.onSurfaceVariant,
    };
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HkSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsTileIcon(icon: icon, color: color),
                const SizedBox(width: HkSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: HkSpacing.space4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: HkSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                spacing: HkSpacing.space4,
                runSpacing: HkSpacing.space4,
                children: [
                  hk_ui.StatusPill(
                    label: _effectiveCapabilityLabel(context, state),
                    color: color,
                    compact: true,
                  ),
                  if (onFix != null)
                    TextButton(onPressed: onFix, child: Text(context.l10n.fix)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _effectiveCapabilityLabel(
  BuildContext context,
  EffectiveCapabilityState state,
) {
  return switch (state) {
    EffectiveCapabilityState.active => context.l10n.allowed,
    EffectiveCapabilityState.degraded => context.l10n.limited,
    EffectiveCapabilityState.blocked => context.l10n.blocked,
    EffectiveCapabilityState.disabledByUser => context.l10n.disabled,
    EffectiveCapabilityState.notConfigured => context.l10n.notSet,
    EffectiveCapabilityState.unavailable => context.l10n.unavailable,
  };
}

String _minutesLabel(BuildContext context, int minutes) {
  final clamped = minutes.clamp(0, 1439).toInt();
  return MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60));
}

TimeOfDay _timeOfDayFromMinutes(int minutes) {
  final clamped = minutes.clamp(0, 1439).toInt();
  return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
}

int _minutesFromTimeOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

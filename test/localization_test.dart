import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/notification_localization.dart';

void main() {
  test(
    'English and Arabic ARB files have exact key and placeholder parity',
    () {
      final english = _arb('lib/l10n/app_en.arb');
      final arabic = _arb('lib/l10n/app_ar.arb');
      final englishKeys = english.keys.where(_isMessageKey).toSet();
      final arabicKeys = arabic.keys.where(_isMessageKey).toSet();

      expect(arabicKeys, englishKeys);
      expect(englishKeys.length, greaterThanOrEqualTo(650));
      for (final key in englishKeys) {
        final englishValue = english[key] as String;
        final arabicValue = arabic[key] as String;
        expect(arabicValue.trim(), isNotEmpty, reason: key);
        expect(
          _placeholders(arabicValue),
          _placeholders(englishValue),
          reason: 'Placeholder mismatch for $key',
        );
      }
    },
  );

  test('Arabic ICU plural forms and notification arguments are localized', () {
    final arabic = lookupAppLocalizations(const Locale('ar'));
    expect(arabic.roomCount(0), contains('لا'));
    expect(arabic.roomCount(2), contains('غرفتان'));

    // Test reminderDaysBeforeDue
    expect(arabic.reminderDaysBeforeDue(0), 'في نفس اليوم');
    expect(arabic.reminderDaysBeforeDue(1), contains('يوم واحد'));
    expect(arabic.reminderDaysBeforeDue(2), contains('يومين'));
    expect(arabic.reminderDaysBeforeDue(5), contains('أيام'));
    expect(arabic.reminderDaysBeforeDue(15), contains('يوماً'));

    // Test durationMinutes
    expect(arabic.durationMinutes(1), contains('دقيقة واحدة'));
    expect(arabic.durationMinutes(2), contains('دقيقتان'));
    expect(arabic.durationMinutes(5), contains('دقائق'));
    expect(arabic.durationMinutes(20), contains('دقيقة'));

    // Test recurrenceRules
    expect(arabic.recurrenceDays(1), 'كل يوم');
    expect(arabic.recurrenceDays(2), 'كل يومين');
    expect(arabic.recurrenceDays(5), contains('أيام'));
    expect(arabic.recurrenceWeeks(1), 'كل أسبوع');
    expect(arabic.recurrenceWeeks(2), 'كل أسبوعين');
    expect(arabic.recurrenceMonths(1), 'كل شهر');
    expect(arabic.recurrenceMonths(2), 'كل شهرين');
    expect(arabic.recurrenceYears(1), 'كل سنة');
    expect(arabic.recurrenceYears(2), 'كل سنتين');

    final english = lookupAppLocalizations(const Locale('en'));
    expect(english.reminderDaysBeforeDue(0), 'On the due date');
    expect(english.reminderDaysBeforeDue(1), '1 day before due');
    expect(english.reminderDaysBeforeDue(5), '5 days before due');
    expect(english.durationMinutes(1), '1 minute');
    expect(english.durationMinutes(15), '15 minutes');
    expect(english.recurrenceDays(1), 'Every day');
    expect(english.recurrenceDays(3), 'Every 3 days');
    expect(english.recurrenceWeeks(1), 'Every week');
    expect(english.recurrenceWeeks(2), 'Every 2 weeks');

    final content = localizeInboxNotification(
      arabic,
      InboxNotification(
        id: 'notification-1',
        title: 'Water the basil is overdue',
        body: 'Legacy snapshot',
        kind: 'task',
        createdAt: DateTime.utc(2026, 7, 22),
        messageCode: NotificationMessageCode.taskOverdue.wireValue,
        messageArgs: const {'task': 'Water the basil'},
      ),
    );

    expect(content.title, contains('Water the basil'));
    expect(content.title, contains('تأخرت'));
    expect(content.body, contains('Owntend'));
  });

  test(
    'controlled domain values use localization at presentation boundaries',
    () {
      final taskDetail = File(
        'lib/src/features/maintenance/presentation/task_detail_screen.dart',
      ).readAsStringSync();
      expect(taskDetail, isNot(contains('_categoryLabel')));
      expect(taskDetail, contains('reminderDaysBeforeDue'));
      expect(taskDetail, isNot(contains("'day' : 'days'")));
      expect(taskDetail, isNot(contains(' before due')));

      final thingDetail = File(
        'lib/src/features/assets/presentation/thing_detail_screen.dart',
      ).readAsStringSync();
      expect(thingDetail, isNot(contains('_categoryLabel')));
      expect(thingDetail, contains('durationMinutes'));
      expect(thingDetail, contains('_petSpeciesLabel(context, pet!.species!)'));
      expect(thingDetail, isNot(contains("'minute' : 'minutes'")));

      final assetDialogs = File(
        'lib/src/features/assets/presentation/asset_dialogs.dart',
      ).readAsStringSync();
      expect(assetDialogs, contains('_assetTypeLabel(context, type)'));

      final domainLocalization = File('lib/src/ui/domain_localization.dart')
          .readAsStringSync();
      expect(domainLocalization, contains('localizedAssetTypeLabel'));
      expect(domainLocalization, contains('recurrenceDays(rule.interval)'));
      expect(domainLocalization, contains('recurrenceWeeks(rule.interval)'));
      expect(domainLocalization, contains('recurrenceMonths(rule.interval)'));
      expect(domainLocalization, contains('recurrenceYears(rule.interval)'));

      final components = File('lib/src/ui/components.dart').readAsStringSync();
      expect(components, isNot(contains(" in \${task.room.name}")));
      expect(
        components,
        contains('localizedAssetTypeLabel(context, task.asset.assetType)'),
      );
      expect(components, contains('localizedRecurrenceLabel(context, rule)'));
      expect(components, isNot(contains('localizedCategoryLabel')));
      expect(components, isNot(contains('recurrenceEveryMany(rule.interval')));

      final search = File('lib/src/core/data/search_repository.dart')
          .readAsStringSync();
      expect(search, isNot(contains("'category'")));
      expect(search, contains('تنظيف'));
      expect(search, contains('حيوانات أليفة'));
    },
  );

  test(
    'unknown controlled notifications use the localized generic fallback',
    () {
      final english = lookupAppLocalizations(const Locale('en'));
      final content = localizeInboxNotification(
        english,
        InboxNotification(
          id: 'notification-2',
          title: 'Backend details must not be shown',
          body: 'Raw payload',
          kind: 'system',
          createdAt: DateTime.utc(2026, 7, 22),
          messageCode: 'future_message_code',
        ),
      );

      expect(content.title, english.notificationGenericTitle);
      expect(content.body, english.notificationGenericBody);
    },
  );
}

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

bool _isMessageKey(String key) => !key.startsWith('@');

Set<String> _placeholders(String value) =>
    RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)(?:,|\})')
        .allMatches(value)
        .map((match) => match.group(1)!)
        .toSet();

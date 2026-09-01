import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;

import 'test_theme.dart';

void main() {
  testWidgets(
    'Arabic TaskCard localizes recurrence and avoids English relationship grammar',
    (tester) async {
      final now = DateTime.utc(2026, 8, 16, 12);
      final task = TaskItem(
        plan: MaintenancePlan(
          id: 'task-cleaning',
          currentOccurrenceId: 'occurrence-task-cleaning',
          assetId: 'asset-vacuum',
          title: 'تنظيف الفلتر',
          recurrence: const RecurrenceRule(
            interval: 2,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: now.add(const Duration(days: 2)),
          createdAt: now,
          updatedAt: now,
        ),
        asset: Asset(
          id: 'asset-vacuum',
          name: 'HEPA Purifier',
          roomId: 'room-kitchen',
          createdAt: now,
          updatedAt: now,
        ),
        room: Room(
          id: 'room-kitchen',
          name: 'المطبخ',
          createdAt: now,
          updatedAt: now,
        ),
        status: TaskStatus.upcoming,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: testLightTheme(),
          home: Scaffold(
            body: SizedBox(width: 420, child: hk_ui.TaskCard(task: task)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final arabic = lookupAppLocalizations(const Locale('ar'));
      expect(find.text(arabic.recurrenceDays(2)), findsOneWidget);
      expect(find.text('HEPA Purifier · المطبخ'), findsOneWidget);
      expect(find.textContaining('Legacy category display name'), findsNothing);
      expect(find.textContaining('Cleaning'), findsNothing);
      expect(find.textContaining(' in '), findsNothing);
    },
  );
}

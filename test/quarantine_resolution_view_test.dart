import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/features/auth/presentation/quarantine_resolution_view.dart';

void main() {
  late AppDatabase db;
  late File tempFile;

  setUp(() async {
    tempFile = File(
      '${Directory.systemTemp.path}/quarantine_widget_test_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    db = AppDatabase(executor: NativeDatabase(tempFile));
  });

  tearDown(() async {
    await db.close();
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  });

  Widget buildTestableWidget({required Locale locale, required Widget child}) {
    return ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('renders QuarantineResolutionView in English', (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        locale: const Locale('en'),
        child: QuarantineResolutionView(database: db),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local Data Quarantine'), findsOneWidget);
    expect(find.text('Export Safety Backup'), findsOneWidget);
    expect(find.text('Reset Local Data'), findsOneWidget);
    expect(find.text('Import Data into My Account'), findsOneWidget);
  });

  testWidgets('renders QuarantineResolutionView in Arabic RTL', (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        locale: const Locale('ar'),
        child: QuarantineResolutionView(database: db),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('حجر البيانات المحلية'), findsOneWidget);
    expect(find.text('تصدير نسخة احتياطية آمنة'), findsOneWidget);
    expect(find.text('إعادة ضبط البيانات المحلية'), findsOneWidget);
    expect(find.text('استيراد البيانات إلى حسابي'), findsOneWidget);
  });

  testWidgets('clicking Reset shows confirmation dialog', (tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        locale: const Locale('en'),
        child: QuarantineResolutionView(database: db),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset Local Data'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Are you sure you want to wipe local data? This will clear all un-synced items on this device. Create a backup first if you want to save them.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';

import '../test_theme.dart';

class _ControlledSearchRepository implements SearchRepository {
  final requests = <String, Completer<List<SearchResult>>>{};

  @override
  Future<void> rebuildIndex() async {}

  @override
  Future<List<SearchResult>> search(String query) {
    final completer = Completer<List<SearchResult>>();
    requests[query] = completer;
    return completer.future;
  }
}

void main() {
  testWidgets('an older search response cannot replace newer results', (
    tester,
  ) async {
    final repository = _ControlledSearchRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [searchRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: testLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SearchScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump(const Duration(milliseconds: 221));
    expect(repository.requests, contains('alpha'));

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump(const Duration(milliseconds: 221));
    expect(repository.requests, contains('beta'));

    repository.requests['beta']!.complete(const [
      SearchResult(
        entityType: 'asset',
        entityId: 'asset-beta',
        title: 'Beta kettle',
        snippet: 'Kitchen',
      ),
    ]);
    await tester.pump();
    expect(find.text('Beta kettle'), findsOneWidget);

    repository.requests['alpha']!.complete(const [
      SearchResult(
        entityType: 'asset',
        entityId: 'asset-alpha',
        title: 'Alpha lamp',
        snippet: 'Bedroom',
      ),
    ]);
    await tester.pump();

    expect(find.text('Beta kettle'), findsOneWidget);
    expect(find.text('Alpha lamp'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

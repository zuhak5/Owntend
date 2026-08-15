import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/config/app_config.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/features/auth/presentation/account_screen.dart';
import 'package:owntend/src/features/auth/presentation/auth_providers.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';

import 'test_theme.dart';

void main() {
  setUp(FeedbackCoordinator.instance.resetForTesting);
  tearDown(FeedbackCoordinator.instance.resetForTesting);

  testWidgets('test build keeps the signed-out account screen usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig.test(environment: AppEnvironment.dev),
          ),
          appBuildInfoProvider.overrideWith(
            (ref) async => const AppBuildInfo(
              version: '1.1.0',
              buildNumber: '7',
              databaseSchema: 9,
            ),
          ),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nickname'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('Synchronization'), findsNothing);
    expect(find.text('Owntend account'), findsNothing);
    expect(find.text('Edit account'), findsNothing);
    expect(find.byKey(const ValueKey('sync-with-google')), findsNothing);
    expect(find.text('App 1.1.0 (7) - database schema 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account screen edits and clears nickname', (tester) async {
    String? savedNickname = 'initial';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig.test(environment: AppEnvironment.dev),
          ),
          appBuildInfoProvider.overrideWith(
            (ref) async => const AppBuildInfo(
              version: '1.2.2',
              buildNumber: '14',
              databaseSchema: 14,
            ),
          ),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: AccountScreen(
            profile: const AppProfile(nickname: 'Account Owner'),
            onSaveNickname: (nickname) async => savedNickname = nickname,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nickname'), findsOneWidget);
    expect(find.text('Account Owner'), findsOneWidget);
    expect(find.text('Edit account'), findsNothing);
    expect(find.byTooltip('Change avatar'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('account-nickname-option')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-nickname-field')),
      '  Home Captain  ',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedNickname, 'Home Captain');

    await tester.tap(find.byKey(const ValueKey('account-nickname-option')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(savedNickname, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow account screen keeps account actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig.test(environment: AppEnvironment.dev),
          ),
          appBuildInfoProvider.overrideWith(
            (ref) async => const AppBuildInfo(
              version: '1.2.2',
              buildNumber: '14',
              databaseSchema: 10,
            ),
          ),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing cloud client does not expose synchronization UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig.configured(
              environment: AppEnvironment.dev,
              supabaseUrl: 'http://127.0.0.1:54321',
              supabasePublishableKey: 'sb_publishable_test',
              googleWebClientId: '123-example.apps.googleusercontent.com',
            ),
          ),
          supabaseClientProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );

    expect(find.text('Nickname'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('Synchronization'), findsNothing);
    expect(find.text('Owntend account'), findsNothing);
    expect(find.byKey(const ValueKey('sync-with-google')), findsNothing);
  });

  testWidgets('account deletion requires confirmation and shows progress', (
    tester,
  ) async {
    final auth = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          appConfigProvider.overrideWithValue(
            AppConfig.test(environment: AppEnvironment.dev),
          ),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Owntend account?'), findsOneWidget);
    expect(
      find.textContaining("only show Google's account chooser"),
      findsOneWidget,
    );
    expect(auth.deleteCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.deleteCalls, 0);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pump();

    expect(auth.deleteCalls, 1);
    expect(
      find.byKey(const ValueKey('account-action-progress')),
      findsOneWidget,
    );

    auth.deleteCompleter.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Account deleted.'), findsOneWidget);
  });

  testWidgets('account screen back button handles direct navigation safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig.test(environment: AppEnvironment.dev),
          ),
          appBuildInfoProvider.overrideWith(
            (ref) async => const AppBuildInfo(
              version: '1.1.0',
              buildNumber: '7',
              databaseSchema: 9,
            ),
          ),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pump();

    final backButton = find.byTooltip('Back');
    expect(backButton, findsOneWidget);
    await tester.tap(backButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _FakeAuthRepository implements AuthRepository {
  final deleteCompleter = Completer<void>();
  var deleteCalls = 0;

  @override
  AuthSession? get currentSession =>
      const AuthSession(userId: 'user-1', providers: {'google'});

  @override
  Future<void> deleteAccount() {
    deleteCalls++;
    return deleteCompleter.future;
  }

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut({bool allDevices = false}) async {}

  @override
  Stream<AuthStateChange> watchAuthState() => Stream.value(
    AuthStateChange(
      event: AuthEventType.initialSession,
      session: currentSession,
    ),
  );
}

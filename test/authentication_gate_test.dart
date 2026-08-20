import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/config/app_config.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:owntend/src/features/auth/presentation/auth_providers.dart';
import 'package:owntend/src/features/auth/presentation/authentication_gate.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;

import 'test_theme.dart';

const _onboardingHeroImage = AssetImage(
  'assets/illustrations/owntend-onboarding-hero-target.webp',
);

void main() {
  testWidgets('first launch requires Google sign-in', (tester) async {
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(_app(auth: auth));
    await tester.pump();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Your data stays private and secure.'), findsOneWidget);
    expect(find.textContaining('Supabase'), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-light-theme')), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-dark-theme')), findsNothing);
    expect(
      find.byKey(const ValueKey('onboarding-language-selector')),
      findsOneWidget,
    );
    expect(find.text('English (US)'), findsOneWidget);
    expect(find.text('English'), findsNothing);
    expect(find.text('العربية'), findsNothing);
    expect(find.textContaining('Anonymous'), findsNothing);
    expect(auth.googleSignInCalls, 0);
    expect(
      tester.getSize(find.byKey(const ValueKey('continue-google'))).height,
      56,
    );
  });

  testWidgets('language selector is compact without losing tap targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _app(auth: auth, theme: testLightTheme(), reduceMotion: true),
    );
    await tester.pump();

    final selector = find.byKey(const ValueKey('onboarding-language-selector'));
    final hitTarget = find.byKey(
      const ValueKey('onboarding-language-selector-hit-target'),
    );
    expect(selector, findsOneWidget);
    expect(hitTarget, findsOneWidget);

    final selectorSize = tester.getSize(selector);
    expect(selectorSize.width, lessThanOrEqualTo(240));
    expect(selectorSize.height, lessThanOrEqualTo(48));

    final hitSize = tester.getSize(hitTarget);
    expect(hitSize.height, greaterThanOrEqualTo(48));
    expect(hitSize.width, greaterThanOrEqualTo(48));

    expect(
      tester.getBottomLeft(hitTarget).dy,
      lessThan(tester.getTopLeft(find.text('Your Tasks,')).dy),
    );
  });

  testWidgets('language selector switches immediately in LTR and RTL', (
    tester,
  ) async {
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);
    final changes = <AppLanguage>[];

    await tester.pumpWidget(_localeSwitchingApp(auth: auth, changes: changes));
    await tester.pump();

    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('onboarding-actions'))),
      ),
      TextDirection.ltr,
    );

    await _selectLanguageFromDropdown(
      tester,
      const ValueKey('language-option-ar'),
    );

    expect(changes, [AppLanguage.ar]);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('onboarding-actions'))),
      ),
      TextDirection.rtl,
    );

    await _selectLanguageFromDropdown(
      tester,
      const ValueKey('language-option-en'),
    );

    expect(changes, [AppLanguage.ar, AppLanguage.en]);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('onboarding-actions'))),
      ),
      TextDirection.ltr,
    );
  });

  testWidgets('Google button uses official image asset without arrow', (
    tester,
  ) async {
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(_app(auth: auth));
    await tester.pump();

    final button = find.byKey(const ValueKey('continue-google'));
    final logo = find.byKey(const ValueKey('google-g-logo'));
    expect(button, findsOneWidget);
    expect(logo, findsOneWidget);

    final image = tester.widget<Image>(logo);
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'assets/brand/google-g-logo.png',
    );
    expect(image.fit, BoxFit.contain);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.arrow_forward_rounded),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString().contains('GoogleMark'),
      ),
      findsNothing,
    );
  });

  testWidgets('premium onboarding fits a compact light viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _app(auth: auth, theme: testLightTheme(), reduceMotion: true),
    );
    await tester.pump();
    await _settleOnboardingHero(tester);

    expect(find.image(_onboardingHeroImage), findsOneWidget);
    _expectContainedHero(
      tester,
      const ValueKey('onboarding-hero-illustration'),
    );
    _expectHeroBehind(
      tester,
      const ValueKey('onboarding-hero-illustration'),
      find.text(
        'Organize tasks, routines, and reminders\n'
        'across all your devices, anytime.',
      ),
    );
    expect(find.byType(Scrollable), findsNothing);
    expect(
      find.byKey(const ValueKey('onboarding-privacy-footer')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('onboarding-viewport')),
      matchesGoldenFile('goldens/premium_onboarding_light.png'),
    );
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey('onboarding-privacy-footer')),
          )
          .dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
  });

  testWidgets('premium onboarding uses the full background on a tall phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _app(auth: auth, theme: testLightTheme(), reduceMotion: true),
    );
    await tester.pump();
    await _settleOnboardingHero(tester);

    _expectContainedHero(
      tester,
      const ValueKey('onboarding-hero-illustration'),
    );
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey('onboarding-privacy-footer')),
          )
          .dy,
      lessThanOrEqualTo(932),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('premium onboarding fits a narrow viewport with language', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _app(auth: auth, theme: testLightTheme(), reduceMotion: true),
    );
    await tester.pump();
    await _settleOnboardingHero(tester);

    final benefitTopEdges = [
      tester.getTopLeft(find.text('Any Device')).dy,
      tester.getTopLeft(find.text('Smart Routines')).dy,
      tester.getTopLeft(find.text('Progress Insights')).dy,
    ];
    expect(benefitTopEdges.toSet(), hasLength(1));
    _expectContainedHero(
      tester,
      const ValueKey('onboarding-hero-illustration'),
    );
    _expectHeroBehind(
      tester,
      const ValueKey('onboarding-hero-illustration'),
      find.text(
        'Organize tasks, routines, and reminders\n'
        'across all your devices, anytime.',
      ),
    );
    expect(find.byKey(const ValueKey('onboarding-light-theme')), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-dark-theme')), findsNothing);
    expect(
      find.byKey(const ValueKey('onboarding-language-selector')),
      findsOneWidget,
    );
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('onboarding-viewport')),
      matchesGoldenFile('goldens/premium_onboarding_narrow.png'),
    );
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey('onboarding-privacy-footer')),
          )
          .dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
  });

  testWidgets('premium onboarding renders deterministic Arabic RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _app(
        auth: auth,
        locale: const Locale('ar'),
        theme: testLightTheme(),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    await _settleOnboardingHero(tester);

    expect(find.byType(Scrollable), findsNothing);
    _expectContainedHero(
      tester,
      const ValueKey('onboarding-hero-illustration'),
    );
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('onboarding-actions'))),
      ),
      TextDirection.rtl,
    );
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('English (US)'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('onboarding-viewport')),
      matchesGoldenFile('goldens/premium_onboarding_arabic.png'),
    );
  });

  testWidgets('shell stays locked until Google authentication completes', (
    tester,
  ) async {
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(_app(auth: auth));
    await tester.pumpAndSettle();

    expect(auth.googleSignInCalls, 0);
    expect(auth.currentSession, isNull);
    expect(find.text('Owntend app'), findsNothing);
    expect(find.byKey(const ValueKey('continue-google')), findsOneWidget);
  });

  testWidgets('Continue with Google creates the only cloud session', (
    tester,
  ) async {
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(_app(auth: auth));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('continue-google')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('continue-google')));
    await tester.pumpAndSettle();

    expect(auth.googleSignInCalls, 1);
    expect(auth.currentSession?.isGoogleUser, isTrue);
    expect(find.text('Owntend app'), findsOneWidget);
  });

  testWidgets('existing Google session skips onboarding on later launches', (
    tester,
  ) async {
    final auth = _FakeAuthRepository(
      session: const AuthSession(userId: 'google-user', providers: {'google'}),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(_app(auth: auth));
    await tester.pumpAndSettle();

    expect(find.text('Owntend app'), findsOneWidget);
    expect(find.text('Your Tasks,'), findsNothing);
  });

  testWidgets('first launch exposes language dropdown control only', (
    tester,
  ) async {
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(_app(auth: auth));
    await tester.pump();

    expect(find.byKey(const ValueKey('onboarding-light-theme')), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-dark-theme')), findsNothing);
    expect(
      find.byKey(const ValueKey('onboarding-language-selector')),
      findsOneWidget,
    );
    expect(find.text('English (US)'), findsOneWidget);
    expect(find.text('Arabic'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('onboarding-language-selector-hit-target')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('language-option-en')), findsOneWidget);
    expect(find.byKey(const ValueKey('language-option-ar')), findsOneWidget);
    expect(find.text('Arabic'), findsOneWidget);
  });

  testWidgets('onboarding remains centered on a wide viewport', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _app(auth: auth, theme: testLightTheme(), reduceMotion: true),
    );
    await tester.pump();
    await _settleOnboardingHero(tester);

    final frame = find.byKey(const ValueKey('onboarding-design-frame'));
    expect(tester.getSize(frame).width, lessThanOrEqualTo(640));
    _expectContainedHero(
      tester,
      const ValueKey('onboarding-hero-illustration'),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('onboarding-viewport')),
      matchesGoldenFile('goldens/premium_onboarding_wide.png'),
    );
  });

  testWidgets('short scaled onboarding keeps every section in one viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _app(auth: auth, theme: testLightTheme(), reduceMotion: true),
    );
    await tester.pump();
    await _settleOnboardingHero(tester);

    expect(find.byType(Scrollable), findsNothing);
    for (final copy in [
      'Any Device',
      'Smart Routines',
      'Progress Insights',
      'Access your tasks and routines across all your devices.',
      'Build habits and automate routines that keep you moving.',
      'Track progress, streaks, and goals to stay motivated.',
      'Continue with Google',
    ]) {
      final finder = find.text(copy);
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.getTopLeft(finder).dy, greaterThanOrEqualTo(0));
      expect(tester.getBottomRight(finder).dy, lessThanOrEqualTo(640));
    }
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey('onboarding-privacy-footer')),
          )
          .dy,
      lessThanOrEqualTo(640),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('onboarding-viewport')),
      matchesGoldenFile('goldens/premium_onboarding_short_scaled.png'),
    );
  });

  testWidgets('visual validation golden renders welcome target frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = _FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _app(auth: auth, theme: testLightTheme(), reduceMotion: true),
    );
    await tester.pump();
    await _settleOnboardingHero(tester);
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Your Tasks,'), findsOneWidget);
    expect(find.text('All in Sync'), findsOneWidget);
    _expectContainedHero(
      tester,
      const ValueKey('onboarding-hero-illustration'),
    );
    _expectHeroBehind(
      tester,
      const ValueKey('onboarding-hero-illustration'),
      find.text(
        'Organize tasks, routines, and reminders\n'
        'across all your devices, anytime.',
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('onboarding-viewport')),
      matchesGoldenFile('goldens/visual_welcome_640.png'),
    ).timeout(const Duration(seconds: 10));
  });
}

Future<void> _selectLanguageFromDropdown(
  WidgetTester tester,
  Key optionKey,
) async {
  await tester.tap(
    find.byKey(const ValueKey('onboarding-language-selector-hit-target')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(optionKey));
  await tester.pumpAndSettle();
}

Future<void> _settleOnboardingHero(WidgetTester tester) async {
  final context = tester.element(
    find.byKey(const ValueKey('onboarding-viewport')),
  );
  await tester.runAsync(() async {
    await precacheImage(_onboardingHeroImage, context);
  });
  await tester.pump();
}

void _expectContainedHero(WidgetTester tester, ValueKey<String> key) {
  final hero = find.byKey(key);
  expect(hero, findsOneWidget);

  final topLeft = tester.getTopLeft(hero);
  final heroSize = tester.getSize(hero);
  final viewportSize = tester.view.physicalSize / tester.view.devicePixelRatio;

  expect(topLeft.dx, moreOrLessEquals(0));
  expect(topLeft.dy, moreOrLessEquals(0));
  expect(heroSize.width, moreOrLessEquals(viewportSize.width));
  expect(heroSize.height, moreOrLessEquals(viewportSize.height));
  final image = tester.widget<Image>(
    find.descendant(of: hero, matching: find.image(_onboardingHeroImage)),
  );
  expect(image.fit, BoxFit.contain);
}

void _expectHeroBehind(
  WidgetTester tester,
  ValueKey<String> key,
  Finder above,
) {
  final hero = find.byKey(key);
  expect(hero, findsOneWidget);
  expect(above, findsOneWidget);

  expect(tester.getTopLeft(hero).dy, lessThan(tester.getBottomLeft(above).dy));
}

Widget _app({
  required _FakeAuthRepository auth,
  ThemeData? theme,
  Locale locale = const Locale('en'),
  bool reduceMotion = false,
}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig.configured(
          environment: AppEnvironment.dev,
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'sb_publishable_test',
          googleWebClientId: '123-example.apps.googleusercontent.com',
        ),
      ),
      authRepositoryProvider.overrideWithValue(auth),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme ?? testLightTheme(),
      home: hk_ui.HkMotion(
        reduceMotion: reduceMotion,
        child: AuthenticationGate(
          language: locale.languageCode == 'ar'
              ? AppLanguage.ar
              : AppLanguage.en,
          onLanguageChanged: (_) {},
          child: const Text('Owntend app'),
        ),
      ),
    ),
  );
}

Widget _localeSwitchingApp({
  required _FakeAuthRepository auth,
  required List<AppLanguage> changes,
}) {
  var language = AppLanguage.en;
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig.configured(
          environment: AppEnvironment.dev,
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'sb_publishable_test',
          googleWebClientId: '123-example.apps.googleusercontent.com',
        ),
      ),
      authRepositoryProvider.overrideWithValue(auth),
    ],
    child: StatefulBuilder(
      builder: (context, setState) {
        return MaterialApp(
          locale: Locale(language.name),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: testLightTheme(),
          home: hk_ui.HkMotion(
            reduceMotion: true,
            child: AuthenticationGate(
              language: language,
              onLanguageChanged: (value) {
                changes.add(value);
                setState(() => language = value);
              },
              child: const Text('Owntend app'),
            ),
          ),
        );
      },
    ),
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.session});

  AuthSession? session;
  int googleSignInCalls = 0;
  final _changes = StreamController<AuthStateChange>.broadcast();

  @override
  AuthSession? get currentSession => session;

  @override
  Future<void> signInWithGoogle() async {
    googleSignInCalls++;
    session = const AuthSession(userId: 'google-user', providers: {'google'});
    _changes.add(
      AuthStateChange(event: AuthEventType.signedIn, session: session),
    );
  }

  @override
  Future<void> signOut({bool allDevices = false}) async {
    session = null;
    _changes.add(
      const AuthStateChange(event: AuthEventType.signedOut, session: null),
    );
  }

  @override
  Future<void> deleteAccount() async {}

  @override
  Stream<AuthStateChange> watchAuthState() async* {
    yield AuthStateChange(
      event: AuthEventType.initialSession,
      session: session,
    );
    yield* _changes.stream;
  }

  void dispose() => _changes.close();
}

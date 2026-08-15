// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/observability/observability_config.dart';
import 'package:owntend/src/core/observability/sentry_bootstrap.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  const config = ObservabilityConfig(
    enabled: true,
    dsn: 'https://public@example.ingest.de.sentry.io/123',
    environment: 'prod',
    release: 'app.owntend.mobile@1.3.4+19',
    dist: '19',
    appVersion: '1.3.4',
    tracesSampleRate: 0.05,
  );

  test('configures privacy-preserving SDK options', () {
    final options = SentryFlutterOptions();

    configureOwntendSentryOptions(options, config);

    expect(options.dsn?.toString(), config.dsn);
    expect(options.environment, 'prod');
    expect(options.release, config.release);
    expect(options.dist, '19');
    expect(options.sendDefaultPii, isFalse);
    expect(options.attachScreenshot, isFalse);
    expect(options.attachViewHierarchy, isFalse);
    expect(options.enableUserInteractionTracing, isFalse);
    expect(options.enableUserInteractionBreadcrumbs, isFalse);
    expect(options.enablePrintBreadcrumbs, isFalse);
    expect(options.enableLogs, isFalse);
    expect(options.enableMetrics, isFalse);
    expect(options.profilesSampleRate, 0);
    expect(options.replay.sessionSampleRate, 0);
    expect(options.replay.onErrorSampleRate, 0);
    expect(options.tracePropagationTargets, isEmpty);
    expect(options.beforeSend, isNotNull);
    expect(options.beforeSendTransaction, isNotNull);
    expect(options.beforeBreadcrumb, isNotNull);
  });

  test('initializer failure starts the app once', () async {
    var appRuns = 0;

    await initializeOwntendSentry(
      config: config,
      appRunner: () async => appRuns++,
      initializer: (configure, appRunner) async {
        configure(SentryFlutterOptions());
        throw StateError('controlled initialization failure');
      },
    );

    expect(appRuns, 1);
  });

  test('initializer cannot run the app twice', () async {
    var appRuns = 0;

    await initializeOwntendSentry(
      config: config,
      appRunner: () async => appRuns++,
      initializer: (configure, appRunner) async {
        configure(SentryFlutterOptions());
        await appRunner();
        await appRunner();
      },
    );

    expect(appRuns, 1);
  });

  test(
    'initializer timeout starts the app without waiting indefinitely',
    () async {
      var appRuns = 0;
      final releaseInitializer = Completer<void>();

      await initializeOwntendSentry(
        config: config,
        appRunner: () async => appRuns++,
        initializationTimeout: const Duration(milliseconds: 1),
        initializer: (configure, appRunner) async {
          configure(SentryFlutterOptions());
          await releaseInitializer.future;
          await appRunner();
        },
      );

      expect(appRuns, 1);
      releaseInitializer.complete();
      await Future<void>.delayed(Duration.zero);
      expect(appRuns, 1);
    },
  );
}

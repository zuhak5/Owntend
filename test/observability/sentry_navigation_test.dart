import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/observability/sentry_navigation.dart';

void main() {
  test('normalizes identifier routes and removes queries', () {
    expect(
      normalizeSentryRoute(
        '/assets/room/7f66f02e-6b71-4adb-a7ba-b962c837b131?tab=history',
      ),
      '/assets/room/:id',
    );
    expect(normalizeSentryRoute('/maintenance/42'), '/maintenance/:id');
    expect(normalizeSentryRoute('/maintenance?filter=late'), '/maintenance');
  });

  test('keeps known routes stable and bounds unknown routes', () {
    expect(normalizeSentryRoute('/account'), '/account');
    expect(normalizeSentryRoute('/'), '/');
    expect(normalizeSentryRoute('/permissions/setup'), '/permissions/setup');
    expect(
      normalizeSentryRoute('/permissions/setup?flow=initial'),
      '/permissions/setup',
    );
    expect(normalizeSentryRoute('/غرفة/المطبخ'), '/unknown');
    expect(normalizeSentryRoute('/unbounded/value'), '/unknown');
  });
}

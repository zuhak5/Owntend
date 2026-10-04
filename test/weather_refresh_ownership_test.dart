import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/weather_service.dart';

void main() {
  late AppDatabase db;
  late DriftSettingsRepository settings;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    settings = DriftSettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'malformed successful weather response cannot replace valid cache',
    () async {
      await settings.setHomeLocation(_locationA);
      var response = _weatherResponse(27);
      final weather = OpenMeteoWeatherRepository(
        db: db,
        settingsRepository: settings,
        httpClient: MockClient((_) async => response),
      );
      final original = await weather.refreshWeather();
      expect(original?.temperature, 27);
      for (final body in [
        '{}',
        '{"current":{"temperature_2m":null},"daily":{}}',
        '{"current":{},"daily":{"time":["invalid-date"]}}',
      ]) {
        response = http.Response(body, 200);
        final refreshed = await weather.refreshWeather();
        expect(refreshed?.temperature, 27);
        expect(refreshed?.updatedAt, original?.updatedAt);
        expect((await weather.cachedWeather())?.updatedAt, original?.updatedAt);
      }
    },
  );

  test(
    'malformed successful weather without a cache remains unavailable',
    () async {
      await settings.setHomeLocation(_locationA);
      final weather = OpenMeteoWeatherRepository(
        db: db,
        settingsRepository: settings,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await weather.refreshWeather(), isNull);
      expect(await weather.cachedWeather(), isNull);
    },
  );

  test('forecast alignment, dates and numeric types are validated', () async {
    await settings.setHomeLocation(_locationA);
    var response = _weatherResponse(27);
    final weather = OpenMeteoWeatherRepository(
      db: db,
      settingsRepository: settings,
      httpClient: MockClient((_) async => response),
    );
    final original = await weather.refreshWeather();
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (data) => (data['current'] as Map)['temperature_2m'] = '27',
      (data) => (data['current'] as Map)['wind_speed_10m'] = null,
      (data) => (data['current'] as Map)['weather_code'] = 1.5,
      (data) => (data['daily'] as Map)['time'] = ['2026-01-01'],
      (data) {
        final daily = data['daily'] as Map;
        for (final key in daily.keys.toList()) {
          daily[key] = key == 'time' ? ['2026-02-30'] : [0];
        }
      },
    ]) {
      final data =
          jsonDecode(_weatherResponse(30).body) as Map<String, dynamic>;
      mutate(data);
      response = http.Response(jsonEncode(data), 200);
      expect((await weather.refreshWeather())?.updatedAt, original?.updatedAt);
      expect((await weather.cachedWeather())?.temperature, 27);
    }
    response = _weatherResponse(0);
    expect((await weather.refreshWeather())?.temperature, 0);
  });

  test('an old completion is discarded after home location changes', () async {
    await settings.setHomeLocation(_locationA);
    final aStarted = Completer<void>();
    final aResponse = Completer<http.Response>();
    final weather = OpenMeteoWeatherRepository(
      db: db,
      settingsRepository: settings,
      httpClient: MockClient((request) {
        if (request.url.queryParameters['latitude'] == '33.32') {
          if (!aStarted.isCompleted) aStarted.complete();
          return aResponse.future;
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    final aRefresh = weather.refreshWeather();
    await aStarted.future;
    await settings.setHomeLocation(_locationB);
    aResponse.complete(_weatherResponse(10));
    await aRefresh;

    expect(await weather.cachedWeather(), isNull);
  });

  test('B completion remains cached when delayed A finishes later', () async {
    await settings.setHomeLocation(_locationA);
    final aStarted = Completer<void>();
    final bStarted = Completer<void>();
    final aResponse = Completer<http.Response>();
    final bResponse = Completer<http.Response>();
    final weather = OpenMeteoWeatherRepository(
      db: db,
      settingsRepository: settings,
      httpClient: MockClient((request) {
        switch (request.url.queryParameters['latitude']) {
          case '33.32':
            if (!aStarted.isCompleted) aStarted.complete();
            return aResponse.future;
          case '35.69':
            if (!bStarted.isCompleted) bStarted.complete();
            return bResponse.future;
          default:
            throw StateError('Unexpected request: ${request.url}');
        }
      }),
    );

    final aRefresh = weather.refreshWeather();
    await aStarted.future;
    await settings.setHomeLocation(_locationB);
    final bRefresh = weather.refreshWeather();
    await bStarted.future;

    bResponse.complete(_weatherResponse(20));
    await bRefresh;
    expect((await weather.cachedWeather())?.location.label, 'B');
    expect((await weather.cachedWeather())?.temperature, 20);

    aResponse.complete(_weatherResponse(10));
    await aRefresh;

    final cached = await weather.cachedWeather();
    expect(cached?.location.label, 'B');
    expect(cached?.temperature, 20);
  });

  test('same normalized location coalesces active HTTP work', () async {
    await settings.setHomeLocation(_locationA);
    final requestStarted = Completer<void>();
    final response = Completer<http.Response>();
    var requestCount = 0;
    final weather = OpenMeteoWeatherRepository(
      db: db,
      settingsRepository: settings,
      httpClient: MockClient((_) {
        requestCount++;
        if (!requestStarted.isCompleted) requestStarted.complete();
        return response.future;
      }),
    );

    final first = weather.refreshWeather();
    final second = weather.refreshWeather();
    await requestStarted.future;
    final third = weather.refreshWeather();

    response.complete(_weatherResponse(15));
    await Future.wait([first, second, third]);

    expect(requestCount, 1);
  });

  test('failed B request does not let stale A persist afterward', () async {
    await settings.setHomeLocation(_locationA);
    final aStarted = Completer<void>();
    final bStarted = Completer<void>();
    final aResponse = Completer<http.Response>();
    final bResponse = Completer<http.Response>();
    final weather = OpenMeteoWeatherRepository(
      db: db,
      settingsRepository: settings,
      httpClient: MockClient((request) {
        switch (request.url.queryParameters['latitude']) {
          case '33.32':
            if (!aStarted.isCompleted) aStarted.complete();
            return aResponse.future;
          case '35.69':
            if (!bStarted.isCompleted) bStarted.complete();
            return bResponse.future;
          default:
            throw StateError('Unexpected request: ${request.url}');
        }
      }),
    );

    final aRefresh = weather.refreshWeather();
    await aStarted.future;
    await settings.setHomeLocation(_locationB);
    final bRefresh = weather.refreshWeather();
    await bStarted.future;

    bResponse.complete(http.Response('{}', 503));
    await bRefresh;
    aResponse.complete(_weatherResponse(10));
    await aRefresh;

    expect(await weather.cachedWeather(), isNull);
  });
}

const _locationA = HomeLocation(
  label: 'A',
  latitude: 33.3152,
  longitude: 44.3661,
  timezone: 'Asia/Baghdad',
  source: 'manual',
);

const _locationB = HomeLocation(
  label: 'B',
  latitude: 35.6892,
  longitude: 51.3890,
  timezone: 'Asia/Tehran',
  source: 'manual',
);

http.Response _weatherResponse(double temperature) {
  return http.Response(
    jsonEncode({
      'timezone': 'UTC',
      'current': {
        'temperature_2m': temperature,
        'apparent_temperature': temperature,
        'relative_humidity_2m': 40,
        'precipitation': 0,
        'weather_code': 1,
        'wind_speed_10m': 5,
      },
      'daily': <String, Object?>{
        'time': <String>[],
        'weather_code': <int>[],
        'temperature_2m_max': <double>[],
        'temperature_2m_min': <double>[],
        'precipitation_probability_max': <int>[],
        'wind_speed_10m_max': <double>[],
      },
    }),
    200,
  );
}

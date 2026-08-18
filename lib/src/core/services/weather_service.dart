import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:owntend/l10n/app_localizations.dart';

import '../database/app_database.dart';
import '../domain/contracts.dart';
import '../domain/models.dart';

HomeLocation privacyReducedLocation(HomeLocation location) {
  final lat = double.parse(location.latitude.toStringAsFixed(2));
  final lng = double.parse(location.longitude.toStringAsFixed(2));
  return HomeLocation(
    label: location.label,
    latitude: lat,
    longitude: lng,
    timezone: location.timezone,
    source: location.source,
  );
}

typedef _WeatherRequestKey = ({
  String label,
  double latitude,
  double longitude,
  String? timezone,
  String source,
});

_WeatherRequestKey _weatherRequestKey(HomeLocation location) {
  return (
    label: location.label,
    latitude: location.latitude,
    longitude: location.longitude,
    timezone: location.timezone,
    source: location.source,
  );
}

class OpenMeteoWeatherRepository implements WeatherRepository {
  OpenMeteoWeatherRepository({
    required this.db,
    required this.settingsRepository,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final AppDatabase db;
  final SettingsRepository settingsRepository;
  final http.Client _httpClient;
  Future<WeatherSnapshot?>? _locationSelectionInFlight;
  final _refreshInFlightByLocation =
      <_WeatherRequestKey, Future<WeatherSnapshot?>>{};

  @override
  Stream<WeatherSnapshot?> watchWeather() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('weather_cache'));
    return query
        .watchSingleOrNull()
        .map((row) => _snapshotFromValue(row?.value))
        .distinct(
          (previous, next) =>
              previous?.updatedAt == next?.updatedAt &&
              previous?.location.latitude == next?.location.latitude &&
              previous?.location.longitude == next?.location.longitude,
        );
  }

  @override
  Future<WeatherSnapshot?> cachedWeather() async {
    final row =
        await (db.select(db.settings)
              ..where((setting) => setting.key.equals('weather_cache')))
            .getSingleOrNull();
    return _snapshotFromValue(row?.value);
  }

  @override
  Future<WeatherSnapshot?> refreshWeather() {
    final selecting = _locationSelectionInFlight;
    if (selecting != null) {
      return selecting;
    }

    final completer = Completer<WeatherSnapshot?>();
    final selection = completer.future;
    _locationSelectionInFlight = selection;
    unawaited(
      settingsRepository.homeLocation().then<void>(
        (rawLocation) {
          if (identical(_locationSelectionInFlight, selection)) {
            _locationSelectionInFlight = null;
          }
          completer.complete(_refreshWeatherForLocation(rawLocation));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_locationSelectionInFlight, selection)) {
            _locationSelectionInFlight = null;
          }
          completer.completeError(error, stackTrace);
        },
      ),
    );
    return selection;
  }

  Future<WeatherSnapshot?> _refreshWeatherForLocation(
    HomeLocation? rawLocation,
  ) {
    if (rawLocation == null) {
      return cachedWeather();
    }
    final location = privacyReducedLocation(rawLocation);
    final requestKey = _weatherRequestKey(location);
    final activeRefresh = _refreshInFlightByLocation[requestKey];
    if (activeRefresh != null) {
      return activeRefresh;
    }

    late final Future<WeatherSnapshot?> refresh;
    refresh = _performWeatherRefresh(location, requestKey).whenComplete(() {
      if (identical(_refreshInFlightByLocation[requestKey], refresh)) {
        _refreshInFlightByLocation.remove(requestKey);
      }
    });
    _refreshInFlightByLocation[requestKey] = refresh;
    return refresh;
  }

  Future<WeatherSnapshot?> _performWeatherRefresh(
    HomeLocation location,
    _WeatherRequestKey requestKey,
  ) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': location.latitude.toStringAsFixed(2),
      'longitude': location.longitude.toStringAsFixed(2),
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max',
      'timezone': 'auto',
      'forecast_days': '7',
    });
    try {
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return await cachedWeather();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return await cachedWeather();
      }
      final snapshot = _snapshotFromOpenMeteo(decoded, location);
      final stored = await _storeSnapshotIfCurrent(requestKey, snapshot);
      if (!stored) {
        return await cachedWeather();
      }
      return snapshot;
    } catch (_) {
      return await cachedWeather();
    }
  }

  Future<bool> _storeSnapshotIfCurrent(
    _WeatherRequestKey requestKey,
    WeatherSnapshot snapshot,
  ) {
    return db.transaction(() async {
      final currentRawLocation = await settingsRepository.homeLocation();
      if (currentRawLocation == null) {
        return false;
      }
      final currentLocation = privacyReducedLocation(currentRawLocation);
      if (_weatherRequestKey(currentLocation) != requestKey) {
        return false;
      }
      await _setSetting('weather_cache', jsonEncode(_snapshotToJson(snapshot)));
      return true;
    });
  }

  @override
  Future<List<HomeLocation>> searchLocations(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      return const [];
    }
    final language = await _languageCode();
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': trimmed,
      'count': '8',
      'language': language,
      'format': 'json',
    });
    try {
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const [];
      }
      final results = decoded['results'];
      if (results is! List) {
        return const [];
      }
      return [
        for (final item in results.whereType<Map<String, dynamic>>())
          if ((item['latitude'] as num?) != null &&
              (item['longitude'] as num?) != null)
            privacyReducedLocation(
              HomeLocation(
                label: [item['name'], item['admin1'], item['country_code']]
                    .where((part) => part != null && '$part'.trim().isNotEmpty)
                    .join(', '),
                latitude: (item['latitude'] as num).toDouble(),
                longitude: (item['longitude'] as num).toDouble(),
                timezone: item['timezone'] as String?,
                source: 'manual',
              ),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<HomeLocation?> useDeviceLocation() async {
    return useCurrentLocationHomeArea();
  }

  @override
  Future<HomeLocation?> useCurrentLocationHomeArea() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final rawLat = double.parse(position.latitude.toStringAsFixed(2));
      final rawLng = double.parse(position.longitude.toStringAsFixed(2));
      final label = await _deviceLocationLabel(rawLat, rawLng);
      final location = HomeLocation(
        label: label,
        latitude: rawLat,
        longitude: rawLng,
        source: 'device',
      );
      await settingsRepository.setHomeLocation(location);
      unawaited(refreshWeather());
      return location;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setSetting(String key, String value) async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  WeatherSnapshot _snapshotFromOpenMeteo(
    Map<String, dynamic> data,
    HomeLocation location,
  ) {
    final current = data['current'] as Map<String, dynamic>? ?? const {};
    final daily = data['daily'] as Map<String, dynamic>? ?? const {};
    final dates = (daily['time'] as List?) ?? const [];
    final codes = (daily['weather_code'] as List?) ?? const [];
    final maxTemps = (daily['temperature_2m_max'] as List?) ?? const [];
    final minTemps = (daily['temperature_2m_min'] as List?) ?? const [];
    final precip =
        (daily['precipitation_probability_max'] as List?) ?? const [];
    final wind = (daily['wind_speed_10m_max'] as List?) ?? const [];
    final responseTimezone = data['timezone'];
    final resolvedLocation = HomeLocation(
      label: location.label,
      latitude: location.latitude,
      longitude: location.longitude,
      timezone: responseTimezone is String && responseTimezone.trim().isNotEmpty
          ? responseTimezone
          : location.timezone,
      source: location.source,
    );
    return WeatherSnapshot(
      location: resolvedLocation,
      updatedAt: DateTime.now(),
      temperature: _double(current['temperature_2m']),
      apparentTemperature: _double(current['apparent_temperature']),
      weatherCode: _int(current['weather_code']),
      windSpeed: _double(current['wind_speed_10m']),
      precipitation: _double(current['precipitation']),
      humidity: _int(current['relative_humidity_2m']),
      forecast: [
        for (var index = 0; index < dates.length; index++)
          WeatherForecastDay(
            date: DateTime.tryParse('${dates[index]}') ?? DateTime.now(),
            weatherCode: _int(index < codes.length ? codes[index] : null),
            temperatureMax: _double(
              index < maxTemps.length ? maxTemps[index] : null,
            ),
            temperatureMin: _double(
              index < minTemps.length ? minTemps[index] : null,
            ),
            precipitationProbabilityMax: _int(
              index < precip.length ? precip[index] : null,
            ),
            windSpeedMax: _double(index < wind.length ? wind[index] : null),
          ),
      ],
    );
  }

  WeatherSnapshot? _snapshotFromValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      final location = decoded['location'] as Map<String, dynamic>;
      return WeatherSnapshot(
        location: HomeLocation(
          label: location['label'] as String,
          latitude: (location['latitude'] as num).toDouble(),
          longitude: (location['longitude'] as num).toDouble(),
          timezone: location['timezone'] as String?,
          source: (location['source'] as String?) ?? 'manual',
        ),
        updatedAt: DateTime.parse(decoded['updatedAt'] as String),
        temperature: _double(decoded['temperature']),
        apparentTemperature: _double(decoded['apparentTemperature']),
        weatherCode: _int(decoded['weatherCode']),
        windSpeed: _double(decoded['windSpeed']),
        precipitation: _double(decoded['precipitation']),
        humidity: _int(decoded['humidity']),
        forecast: [
          for (final item
              in (decoded['forecast'] as List? ?? const [])
                  .whereType<Map<String, dynamic>>())
            WeatherForecastDay(
              date: DateTime.parse(item['date'] as String),
              weatherCode: _int(item['weatherCode']),
              temperatureMax: _double(item['temperatureMax']),
              temperatureMin: _double(item['temperatureMin']),
              precipitationProbabilityMax: _int(
                item['precipitationProbabilityMax'],
              ),
              windSpeedMax: _double(item['windSpeedMax']),
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _snapshotToJson(WeatherSnapshot snapshot) {
    return {
      'location': {
        'label': snapshot.location.label,
        'latitude': snapshot.location.latitude,
        'longitude': snapshot.location.longitude,
        'timezone': snapshot.location.timezone,
        'source': snapshot.location.source,
      },
      'updatedAt': snapshot.updatedAt.toIso8601String(),
      'temperature': snapshot.temperature,
      'apparentTemperature': snapshot.apparentTemperature,
      'weatherCode': snapshot.weatherCode,
      'windSpeed': snapshot.windSpeed,
      'precipitation': snapshot.precipitation,
      'humidity': snapshot.humidity,
      'forecast': [
        for (final day in snapshot.forecast)
          {
            'date': day.date.toIso8601String(),
            'weatherCode': day.weatherCode,
            'temperatureMax': day.temperatureMax,
            'temperatureMin': day.temperatureMin,
            'precipitationProbabilityMax': day.precipitationProbabilityMax,
            'windSpeedMax': day.windSpeedMax,
          },
      ],
    };
  }

  double _double(Object? value) => value is num ? value.toDouble() : 0;

  int _int(Object? value) => value is num ? value.round() : 0;

  Future<String> _deviceLocationLabel(double lat, double lng) async {
    final language = await _languageCode();
    final l10n = lookupAppLocalizations(Locale(language));
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': lat.toStringAsFixed(2),
      'lon': lng.toStringAsFixed(2),
      'format': 'jsonv2',
      'zoom': '10',
      'accept-language': language,
    });
    try {
      final response = await _httpClient
          .get(uri, headers: {'User-Agent': 'Owntend/1.0'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return l10n.deviceLocation;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return l10n.deviceLocation;
      }
      final address = decoded['address'];
      if (address is! Map<String, dynamic>) {
        return _stringOrFallback(decoded['name'], l10n.deviceLocation);
      }
      final label = [
        address['city'] ??
            address['town'] ??
            address['village'] ??
            address['suburb'] ??
            address['county'],
        address['state'],
        address['country_code']?.toString().toUpperCase(),
      ].where((part) => part != null && '$part'.trim().isNotEmpty).join(', ');
      return label.isEmpty ? l10n.deviceLocation : label;
    } catch (_) {
      return l10n.deviceLocation;
    }
  }

  Future<String> _languageCode() async {
    final preference = await settingsRepository.appLocalePreference();
    if (preference.isExplicit) return preference.language.name;
    return PlatformDispatcher.instance.locale.languageCode.toLowerCase() ==
            AppLanguage.ar.name
        ? AppLanguage.ar.name
        : AppLanguage.en.name;
  }

  String _stringOrFallback(Object? value, String fallback) {
    final text = value == null ? '' : '$value'.trim();
    return text.isEmpty ? fallback : text;
  }
}

String weatherSummary(int code) {
  return switch (code) {
    0 => 'Clear',
    1 || 2 => 'Partly cloudy',
    3 => 'Cloudy',
    45 || 48 => 'Fog',
    51 || 53 || 55 || 56 || 57 => 'Drizzle',
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => 'Rain',
    71 || 73 || 75 || 77 || 85 || 86 => 'Snow',
    95 || 96 || 99 => 'Storms',
    _ => 'Weather',
  };
}

String seasonFor(DateTime value) {
  return switch (value.month) {
    12 || 1 || 2 => 'winter',
    3 || 4 || 5 => 'spring',
    6 || 7 || 8 => 'summer',
    _ => 'fall',
  };
}

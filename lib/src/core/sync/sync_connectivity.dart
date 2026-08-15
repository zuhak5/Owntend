import 'package:connectivity_plus/connectivity_plus.dart';

abstract interface class SyncConnectivity {
  Future<bool> isOnline();
  Stream<bool> watchOnline();
}

class AlwaysOnlineSyncConnectivity implements SyncConnectivity {
  const AlwaysOnlineSyncConnectivity();

  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> watchOnline() => Stream.value(true);
}

class PlatformSyncConnectivity implements SyncConnectivity {
  PlatformSyncConnectivity([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isOnline() async {
    return _hasNetwork(await _connectivity.checkConnectivity());
  }

  @override
  Stream<bool> watchOnline() async* {
    yield await isOnline();
    yield* _connectivity.onConnectivityChanged.map(_hasNetwork).distinct();
  }
}

bool _hasNetwork(List<ConnectivityResult> results) {
  return results.any((result) => result != ConnectivityResult.none);
}

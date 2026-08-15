import 'package:flutter/foundation.dart';

const kAdCacheMaxAge = Duration(minutes: 55);

@immutable
class CachedAd<T> {
  const CachedAd({required this.value, required this.loadedAt});

  final T value;
  final DateTime loadedAt;

  bool isFresh(DateTime now) => now.difference(loadedAt) < kAdCacheMaxAge;
}

class AdLease<T> {
  AdLease(this.value, this._release);

  final T value;
  final void Function(T value) _release;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _release(value);
  }
}

class FullScreenAdLease {
  FullScreenAdLease._(this._owner);

  final FullScreenAdGate _owner;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _owner._release(this);
  }
}

class FullScreenAdGate {
  FullScreenAdLease? _active;

  bool get isLocked => _active != null;

  FullScreenAdLease? tryAcquire() {
    if (_active != null) return null;
    final lease = FullScreenAdLease._(this);
    _active = lease;
    return lease;
  }

  void _release(FullScreenAdLease lease) {
    if (identical(_active, lease)) _active = null;
  }
}

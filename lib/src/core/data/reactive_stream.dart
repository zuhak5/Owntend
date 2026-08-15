import 'dart:async';

const databaseSettleDuration = Duration(milliseconds: 120);

Stream<T> watchReloaded<T>({
  required Iterable<Stream<Object?>> triggers,
  required Future<T> Function() load,
  required int Function(T value) fingerprint,
  Duration settleDuration = databaseSettleDuration,
}) {
  late StreamController<T> controller;
  final subscriptions = <StreamSubscription<Object?>>[];
  Timer? timer;
  var loading = false;
  var reloadPending = false;
  int? lastFingerprint;
  late void Function({bool immediate}) schedule;

  Future<void> emit() async {
    if (loading || controller.isClosed || !controller.hasListener) {
      reloadPending = loading;
      return;
    }
    loading = true;
    try {
      final value = await load();
      if (controller.isClosed || !controller.hasListener) {
        return;
      }
      final nextFingerprint = fingerprint(value);
      if (nextFingerprint != lastFingerprint) {
        lastFingerprint = nextFingerprint;
        controller.add(value);
      }
    } catch (error, stackTrace) {
      if (!controller.isClosed && controller.hasListener) {
        controller.addError(error, stackTrace);
      }
    } finally {
      loading = false;
      if (reloadPending && !controller.isClosed && controller.hasListener) {
        reloadPending = false;
        schedule();
      }
    }
  }

  schedule = ({bool immediate = false}) {
    if (controller.isClosed || !controller.hasListener) {
      return;
    }
    timer?.cancel();
    if (loading) {
      reloadPending = true;
      return;
    }
    if (immediate) {
      unawaited(emit());
    } else {
      timer = Timer(settleDuration, emit);
    }
  };

  controller = StreamController<T>(
    onListen: () {
      for (final trigger in triggers) {
        subscriptions.add(
          trigger.listen(
            (_) => schedule(),
            onError: (Object error, StackTrace stackTrace) {
              if (!controller.isClosed && controller.hasListener) {
                controller.addError(error, stackTrace);
              }
            },
          ),
        );
      }
      schedule(immediate: true);
    },
    onCancel: () async {
      timer?.cancel();
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    },
  );
  return controller.stream;
}

extension SemanticDistinctStream<T> on Stream<T> {
  Stream<T> distinctByFingerprint(int Function(T value) fingerprint) {
    return distinct(
      (previous, next) => fingerprint(previous) == fingerprint(next),
    );
  }
}

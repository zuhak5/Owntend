import 'dart:async';

import '../observability/sentry_logger_bridge.dart';
import '../observability/sentry_scope.dart';
import '../observability/sentry_tracing.dart';
import 'sync_contracts.dart';

class ObservedCloudSyncRepository implements CloudSyncRepository {
  const ObservedCloudSyncRepository(this._delegate);

  final CloudSyncRepository _delegate;

  @override
  Stream<SyncStatus> watchStatus() async* {
    try {
      await for (final status in _delegate.watchStatus()) {
        unawaited(setSentryUiState(syncEnabled: status.enabled));
        yield status;
      }
    } on Object catch (error, stackTrace) {
      reportOperationFailure(
        operation: 'sync_status_stream_failed',
        error: error,
        stackTrace: stackTrace,
        fields: const {'sync_mode': 'automatic', 'execution': 'main'},
      );
      rethrow;
    }
  }

  @override
  Future<SyncStatus> status() => _run<SyncStatus>(
    operation: 'sync.run',
    syncMode: 'status',
    callback: _delegate.status,
  );

  @override
  Future<void> enable() => _run<void>(
    operation: 'sync.initial_hydration',
    syncMode: 'initial_hydration',
    callback: _delegate.enable,
  );

  @override
  Future<void> disable() => _run<void>(
    operation: 'sync.pause',
    syncMode: 'disable',
    callback: _delegate.disable,
  );

  @override
  Future<void> unlink() => _run<void>(
    operation: 'sync.pause',
    syncMode: 'unlink',
    callback: _delegate.unlink,
  );

  @override
  Future<void> retry() => _run<void>(
    operation: 'sync.retry',
    syncMode: 'retry',
    callback: _delegate.retry,
  );

  @override
  Future<void> fullReconcile() => _run<void>(
    operation: 'sync.full_reconcile',
    syncMode: 'full_reconcile',
    callback: _delegate.fullReconcile,
  );

  @override
  Future<void> syncNow() => _run<void>(
    operation: 'sync.manual',
    syncMode: 'manual',
    callback: _delegate.syncNow,
  );

  Future<T> _run<T>({
    required String operation,
    required String syncMode,
    required Future<T> Function() callback,
  }) async {
    try {
      return await traceOwntendOperation<T>(
        operation,
        callback,
        attributes: {'sync_mode': syncMode, 'execution': 'main'},
      );
    } on Object catch (error, stackTrace) {
      reportOperationFailure(
        operation: '${operation.replaceAll('.', '_')}_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {'sync_mode': syncMode, 'execution': 'main'},
      );
      rethrow;
    }
  }
}

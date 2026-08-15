import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../observability/sentry_logger_bridge.dart';
import '../observability/sentry_tracing.dart';
import 'sync_providers.dart';

class CloudSyncBootstrap extends ConsumerStatefulWidget {
  const CloudSyncBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CloudSyncBootstrap> createState() => _CloudSyncBootstrapState();
}

class _CloudSyncBootstrapState extends ConsumerState<CloudSyncBootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(_resumeSync);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      scheduleMicrotask(_resumeSync);
    }
  }

  Future<void> _resumeSync() async {
    final coordinator = ref.read(syncCoordinatorProvider);
    if (coordinator == null) return;
    try {
      await traceOwntendOperation<void>(
        'sync.resume',
        () async => coordinator.onAppResumed(),
        attributes: const {'sync_mode': 'automatic', 'execution': 'main'},
      );
    } on Object catch (error, stackTrace) {
      reportOperationFailure(
        operation: 'sync_resume_failed',
        error: error,
        stackTrace: stackTrace,
        fields: const {'sync_mode': 'automatic', 'execution': 'main'},
      );
      // The coordinator persists and exposes failures through SyncStatus.
      // Startup and the offline app must remain available.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

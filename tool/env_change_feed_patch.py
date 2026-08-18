from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)


path = Path('lib/src/core/sync/sync_coordinator.dart')
text = path.read_text()

text = replace_once(
    text,
    "import 'local_sync_store.dart';\nimport 'supabase_sync_gateway.dart';",
    "import 'change_feed_contract.dart';\n"
    "import 'local_sync_store.dart';\n"
    "import 'local_sync_store_change_feed.dart';\n"
    "import 'supabase_sync_gateway.dart';",
    'imports',
)

text = replace_once(
    text,
    """      if (capability.enabled) {
        return await _pullServerChangeFeed(userId, deviceId, scope: scope);
      }
""",
    """      if (capability.enabled) {
        requireSyncFeedContractVersion(capability.capabilityVersion);
        return await _pullServerChangeFeed(userId, deviceId, scope: scope);
      }
""",
    'capability version gate',
)

text = replace_once(
    text,
    """    var remoteRecordCount = 0;
    var meaningfulRemoteRecordCount = 0;
    var maintenanceChanged = false;
    var currentSeq = await _localStore.getFeedCursor();

    while (true) {
""",
    """    var remoteRecordCount = 0;
    var meaningfulRemoteRecordCount = 0;
    var maintenanceChanged = false;
    final pendingResnapshotHighWater = await _localStore
        .feedResnapshotHighWater();
    if (pendingResnapshotHighWater != null) {
      return _resumeFeedResnapshot(
        userId,
        deviceId,
        scope: scope,
        highWaterSeq: pendingResnapshotHighWater,
      );
    }
    var currentSeq = await _localStore.getFeedCursor();

    while (true) {
""",
    'durable resnapshot resume',
)

text = replace_once(
    text,
    """      if (page.resnapshotRequired) {
        AppLogger.warning(
          'sync_feed_resnapshot_required',
          fields: {
            'since_seq': currentSeq,
            'high_water_seq': page.highWaterSeq,
          },
        );
        await _localStore.setFeedCursor(0);
        return await _pullAllLegacy(
          userId,
          deviceId,
          scope: scope,
          firstSync: true,
          buildHydrationPlan: false,
        );
      }

      if (page.changes.isEmpty) {
""",
    """      if (!page.capabilityEnabled) {
        return _pullAllLegacy(
          userId,
          deviceId,
          scope: scope,
          firstSync: false,
          buildHydrationPlan: false,
        );
      }
      requireSyncFeedContractVersion(page.capabilityVersion);

      if (page.resnapshotRequired) {
        AppLogger.warning(
          'sync_feed_resnapshot_required',
          fields: {
            'since_seq': currentSeq,
            'high_water_seq': page.highWaterSeq,
          },
        );
        await _localStore.resetFeedCursorForResnapshot(
          highWaterSeq: page.highWaterSeq,
        );
        return _resumeFeedResnapshot(
          userId,
          deviceId,
          scope: scope,
          highWaterSeq: page.highWaterSeq,
        );
      }

      if (page.changes.isEmpty) {
""",
    'page capability and resnapshot handling',
)

text = replace_once(
    text,
    """      remoteRecordCount += page.changes.length;
      final allSpecs = [...syncEntitySpecs, profileSyncSpec];
      final pageRecords = <SyncRecord>[];

      for (final change in page.changes) {
        final entity = change['entity_type'] as String?;
        final recordKey = change['record_id'] as String?;
        final opType = change['op_type'] as String?;
        if (entity == null || recordKey == null || opType == null) continue;

        final spec = allSpecs.firstWhere(
          (s) => s.entity == entity,
          orElse: () => profileSyncSpec,
        );

        if (opType == 'DELETE') {
          final now = DateTime.now();
          final dummyRecord = SyncRecord(
            spec: spec,
            recordKey: recordKey,
            clientModifiedAt: now,
            originDeviceId: deviceId,
            deletedAt: now,
            values: {'id': recordKey},
          );
          pageRecords.add(dummyRecord);
          meaningfulRemoteRecordCount++;
        } else {
          final canonical = await _remoteGateway.fetchRecordByKey(
            spec: spec,
            recordKey: recordKey,
            userId: userId,
          );
""",
    """      remoteRecordCount += page.changes.length;
      final pageRecords = <SyncRecord>[];

      for (final change in page.changes) {
        final parsed = parseSyncFeedChange(change);
        final spec = parsed.spec;
        final recordKey = parsed.recordKey;

        if (parsed.operation == 'DELETE') {
          final now = DateTime.now();
          final dummyRecord = SyncRecord(
            spec: spec,
            recordKey: recordKey,
            clientModifiedAt: now,
            originDeviceId: deviceId,
            deletedAt: now,
            values: parsed.keyValues,
          );
          pageRecords.add(dummyRecord);
          meaningfulRemoteRecordCount++;
        } else {
          final canonical = await _remoteGateway.fetchRecordByKey(
            spec: spec,
            recordKey: recordKey,
            userId: userId,
          );
""",
    'strict page change parsing',
)

text = replace_once(
    text,
    """    return _PullOutcome(
      remoteRecordCount: remoteRecordCount,
      meaningfulRemoteRecordCount: meaningfulRemoteRecordCount,
      maintenanceChanged: maintenanceChanged,
    );
  }

  Future<int> runHealingScan(String userId) async {
""",
    """    return _PullOutcome(
      remoteRecordCount: remoteRecordCount,
      meaningfulRemoteRecordCount: meaningfulRemoteRecordCount,
      maintenanceChanged: maintenanceChanged,
    );
  }

  Future<_PullOutcome> _resumeFeedResnapshot(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    required int highWaterSeq,
  }) async {
    final outcome = await _pullAllLegacy(
      userId,
      deviceId,
      scope: scope,
      firstSync: false,
      buildHydrationPlan: false,
      forceFullSnapshot: true,
    );
    await _ensureActiveAccountScope(scope);
    await _reconcileMissedRemoteDeletes(
      userId,
      deviceId,
      scope: scope,
    );
    await _ensureActiveAccountScope(scope);
    await _localStore.completeFeedResnapshot(highWaterSeq);
    return outcome;
  }

  Future<int> runHealingScan(String userId) async {
""",
    'resnapshot completion method',
)

text = replace_once(
    text,
    """  Future<int> runHealingScan(String userId) async {
    final parityResults = await _remoteGateway.validateChangeFeedParity();
    var repairedCount = 0;
    final allSpecs = [...syncEntitySpecs, profileSyncSpec];

    for (final row in parityResults) {
      final isParity = row['is_parity'] as bool? ?? true;
      if (!isParity) {
        final entity = row['entity_type'] as String?;
        if (entity != null) {
          final spec = allSpecs.firstWhere(
            (s) => s.entity == entity,
            orElse: () => profileSyncSpec,
          );
          final records = await _remoteGateway.pullChanges(
            spec: spec,
            userId: userId,
            deviceId: '',
            afterSyncSeq: 0,
            materializeMedia: false,
          );
          for (final record in records) {
            await _localStore.applyRemoteFeedRecord(record);
            repairedCount++;
          }
        }
      }
    }
    return repairedCount;
  }
""",
    """  Future<int> runHealingScan(String userId) async {
    final parityResults = await _remoteGateway.validateChangeFeedParity();
    var repairedCount = 0;

    for (final row in parityResults) {
      final isParity = row['is_parity'] as bool? ?? true;
      if (!isParity) {
        final entity = row['entity_type'];
        if (entity is! String) {
          throw syncFeedProtocolFailure();
        }
        final spec = syncFeedSpecForEntity(entity);
        final records = await _remoteGateway.pullChanges(
          spec: spec,
          userId: userId,
          deviceId: '',
          afterSyncSeq: 0,
          materializeMedia: false,
        );
        for (final record in records) {
          await _localStore.applyRemoteFeedRecord(record);
          repairedCount++;
        }
      }
    }
    return repairedCount;
  }
""",
    'strict healing entity mapping',
)

text = replace_once(
    text,
    """  Future<_PullOutcome> _pullAllLegacy(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    required bool firstSync,
    required bool buildHydrationPlan,
    Set<String>? targetTables,
  }) async {
""",
    """  Future<_PullOutcome> _pullAllLegacy(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    required bool firstSync,
    required bool buildHydrationPlan,
    Set<String>? targetTables,
    bool forceFullSnapshot = false,
  }) async {
""",
    'legacy full snapshot option',
)

text = replace_once(
    text,
    """              final checkpoint = await _localStore.cursorCheckpoint(
                spec.entity,
              );
""",
    """              final checkpoint = forceFullSnapshot
                  ? const (0, null)
                  : await _localStore.cursorCheckpoint(spec.entity);
""",
    'full snapshot zero checkpoints',
)

path.write_text(text)
Path('tool/env_change_feed_patch.py').unlink()
Path('.github/workflows/env-change-feed-patch.yml').unlink()

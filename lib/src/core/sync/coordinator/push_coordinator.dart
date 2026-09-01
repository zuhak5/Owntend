part of '../sync_coordinator.dart';

enum _MutationPushDisposition { applied, terminalHandled }

extension _SyncPushCoordinator on SyncCoordinator {
  Future<bool> _pushPending(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    bool trackHydration = false,
  }) async {
    bool pushedSomething = false;
    await _localStore.enforceMaintenanceHistoryMutationAuthority();
    while (true) {
      await _ensureActiveAccountScope(scope);
      final mutations = await _localStore.pendingMutations();
      if (mutations.isEmpty) return pushedSomething;
      pushedSomething = true;
      var index = 0;
      while (index < mutations.length) {
        final mutation = mutations[index];

        if (mutation.entity == 'maintenance_completion') {
          final payloadJson = mutation.payloadJson;
          if (mutation.operation != 'execute' ||
              payloadJson == null ||
              payloadJson.trim().isEmpty) {
            const failure = SupabaseFailure(
              kind: SupabaseFailureKind.incompatibleSchema,
              message:
                  'A queued maintenance completion has an invalid payload. '
                  'Update Owntend before synchronizing again.',
            );
            await _recordMutationFailure(mutation, failure);
            throw failure;
          }

          try {
            final disposition = await _pushMaintenanceCompletion(
              mutation,
              payloadJson: payloadJson,
              userId: userId,
              deviceId: deviceId,
              scope: scope,
            );
            if (trackHydration) {
              await _localStore.addHydrationUnits(1);
            }
            if (disposition == _MutationPushDisposition.terminalHandled) {
              AppLogger.warning(
                'sync_terminal_mutation_handled',
                fields: {
                  'sync_entity': mutation.entity,
                  'sync_operation': mutation.operation,
                },
              );
            }
          } on _AccountScopeInactive {
            rethrow;
          } on Object catch (error) {
            final failure = _canonicalMutationFailure(
              mutation,
              SupabaseFailure.from(error),
            );
            if (!await _localStore.isMutationFailedVisible(mutation)) {
              await _recordMutationFailure(mutation, failure);
            }
            throw failure;
          }

          index++;
          continue;
        }

        if (mutation.entity == 'maintenance_history_restore') {
          final payloadJson = mutation.payloadJson;
          if (mutation.operation != 'execute' ||
              payloadJson == null ||
              payloadJson.trim().isEmpty) {
            const failure = SupabaseFailure(
              kind: SupabaseFailureKind.incompatibleSchema,
              message: 'A queued maintenance history restore is malformed.',
              retryable: false,
            );
            await _recordMutationFailure(mutation, failure);
            throw failure;
          }
          try {
            final prepared = await _remoteGateway
                .prepareMaintenanceHistoryRestorePayload(
                  payloadJson: payloadJson,
                  userId: userId,
                  deviceId: deviceId,
                );
            await _localStore.prepareMaintenanceHistoryRestore(
              mutation,
              payloadJson: prepared,
              userId: userId,
            );
            final result = await _remoteGateway.restoreMaintenanceHistory(
              payloadJson: prepared,
              userId: userId,
              deviceId: deviceId,
            );
            await _ensureActiveAccountScope(scope);
            if (!result.applied) {
              final conflictReason =
                  result.conflictReason ??
                  'maintenance_history_restore_conflict';
              final failure = SupabaseFailure(
                kind: SupabaseFailureKind.conflict,
                message:
                    'Maintenance history restore conflict: '
                    '$conflictReason.',
                retryable: false,
              );
              await _localStore.markMaintenanceHistoryRestoreConflict(
                mutation,
                conflictReason: conflictReason,
                message: failure.message,
              );
              if (trackHydration) await _localStore.addHydrationUnits(1);
              AppLogger.warning(
                'sync_terminal_mutation_handled',
                fields: {
                  'sync_entity': mutation.entity,
                  'sync_operation': mutation.operation,
                },
              );
              index++;
              continue;
            }
            await _localStore.markMaintenanceHistoryRestoreSucceeded(
              mutation,
              plan: result.plan,
            );
            if (trackHydration) await _localStore.addHydrationUnits(1);
          } on _AccountScopeInactive {
            rethrow;
          } on Object catch (error) {
            final failure = SupabaseFailure.from(error);
            if (!await _localStore.isMutationFailedVisible(mutation)) {
              await _recordMutationFailure(mutation, failure);
            }
            throw failure;
          }
          index++;
          continue;
        }

        if (mutation.entity == 'asset_photo_primary') {
          final payloadJson = mutation.payloadJson;
          if (mutation.operation != 'execute' ||
              payloadJson == null ||
              payloadJson.trim().isEmpty) {
            const failure = SupabaseFailure(
              kind: SupabaseFailureKind.incompatibleSchema,
              message:
                  'A queued primary-photo operation has an invalid payload.',
            );
            await _recordMutationFailure(mutation, failure);
            throw failure;
          }
          try {
            final payload = Map<String, dynamic>.from(
              jsonDecode(payloadJson) as Map,
            );
            final assetId = payload['asset_id'] as String?;
            final photoId = payload['photo_id'] as String?;
            if (assetId == null ||
                photoId == null ||
                assetId != mutation.recordKey) {
              throw const SupabaseFailure(
                kind: SupabaseFailureKind.incompatibleSchema,
                message: 'A queued primary-photo operation is malformed.',
              );
            }
            await _localStore.markMutationInFlight(mutation, userId: userId);
            final response = await _remoteGateway.setPrimaryAssetPhoto(
              assetId: assetId,
              photoId: photoId,
            );
            await _ensureActiveAccountScope(scope);
            final rawPhotos = response['photos'];
            if (rawPhotos is! List) {
              throw const FormatException(
                'The primary-photo RPC omitted canonical photo rows.',
              );
            }
            final spec = syncSpecByEntity['asset_photo']!;
            final photos = <SyncRecord>[];
            for (final raw in rawPhotos) {
              if (raw is! Map) {
                throw const FormatException(
                  'The primary-photo RPC returned an invalid photo row.',
                );
              }
              final row = Map<String, dynamic>.from(raw);
              if (row['user_id'] != userId || row['asset_id'] != assetId) {
                throw const SupabaseFailure(
                  kind: SupabaseFailureKind.permissionDenied,
                  message: 'The cloud returned primary-photo data for another scope.',
                );
              }
              photos.add(SyncRecord.fromRemote(spec, row));
            }
            if (!photos.any(
              (record) =>
                  record.recordKey == photoId &&
                  record.values['is_primary'] == true,
            )) {
              throw const FormatException(
                'The primary-photo RPC did not confirm the selected photo.',
              );
            }
            await _localStore.markAssetPhotoPrimarySucceeded(
              mutation,
              photos: photos,
            );
            if (trackHydration) await _localStore.addHydrationUnits(1);
            return true;
          } on _AccountScopeInactive {
            rethrow;
          } on Object catch (error) {
            final failure = SupabaseFailure.from(error);
            await _recordMutationFailure(mutation, failure);
            rethrow;
          }
        }

        if (mutation.entity == 'maintenance_undo') {
          final payloadJson = mutation.payloadJson;
          if (mutation.operation != 'execute' ||
              payloadJson == null ||
              payloadJson.trim().isEmpty) {
            const failure = SupabaseFailure(
              kind: SupabaseFailureKind.incompatibleSchema,
              message:
                  'A queued maintenance undo has an invalid payload. '
                  'Update Owntend before synchronizing again.',
            );
            await _recordMutationFailure(mutation, failure);
            throw failure;
          }
          try {
            final disposition = await _pushMaintenanceUndo(
              mutation,
              payloadJson: payloadJson,
              userId: userId,
              deviceId: deviceId,
              scope: scope,
            );
            if (trackHydration) {
              await _localStore.addHydrationUnits(1);
            }
            if (disposition == _MutationPushDisposition.terminalHandled) {
              AppLogger.warning(
                'sync_terminal_mutation_handled',
                fields: {
                  'sync_entity': mutation.entity,
                  'sync_operation': mutation.operation,
                },
              );
            }
            // The undo acknowledgement removes generic guard rows that may
            // already be present in this in-memory batch. Stop using this snapshot
            // and re-read the outbox immediately.
            break;
          } on _AccountScopeInactive {
            rethrow;
          } on Object catch (error) {
            final failure = SupabaseFailure.from(error);
            if (!await _localStore.isMutationFailedVisible(mutation)) {
              await _recordMutationFailure(mutation, failure);
            }
            throw failure;
          }
        }

        if (mutation.operation == 'upsert') {
          final shadow = await _localStore.shadow(
            mutation.entity,
            mutation.recordKey,
          );
          final spec = syncSpecByEntity[mutation.entity];
          if (shadow == null &&
              spec != null &&
              // Asset creation is server-authoritative and must go through
              // the idempotent aggregate RPC one operation at a time.
              spec.entity != 'asset' &&
              spec.entity != 'asset_photo' &&
              spec.entity != 'profile') {
            final batchMutations = <LocalSyncMutation>[];
            final batchRecords = <SyncRecord>[];
            while (index < mutations.length &&
                batchMutations.length < 100 &&
                mutations[index].operation == 'upsert' &&
                mutations[index].entity == mutation.entity &&
                await _localStore.shadow(
                      mutations[index].entity,
                      mutations[index].recordKey,
                    ) ==
                    null) {
              final candidate = mutations[index];
              final record = await _localStore.readMutation(
                candidate,
                deviceId,
              );
              if (record == null || record.isDeleted) break;
              batchMutations.add(candidate);
              batchRecords.add(record);
              index++;
            }
            if (batchRecords.isNotEmpty) {
              BatchWriteResult batchResult;
              try {
                batchResult = await _remoteGateway.writeNewBatch(
                  records: batchRecords,
                  userId: userId,
                  deviceId: deviceId,
                );
                await _ensureActiveAccountScope(scope);
              } on _AccountScopeInactive {
                rethrow;
              } on Object catch (error) {
                final failure = SupabaseFailure.from(error);
                for (final item in batchMutations) {
                  await _recordMutationFailure(item, failure);
                }
                rethrow;
              }
              if (batchResult is BatchWriteSuccess) {
                final byKey = {
                  for (final record in batchResult.records)
                    record.recordKey: record,
                };
                for (var offset = 0; offset < batchMutations.length; offset++) {
                  final item = batchMutations[offset];
                  final inserted = byKey[item.recordKey];
                  if (inserted != null &&
                      !batchResult.replayedRecordKeys.contains(
                        item.recordKey,
                      )) {
                    await _localStore.markMutationSucceeded(item, inserted);
                    continue;
                  }
                  await _reconcileBatchCreationReplay(
                    mutation: item,
                    local: batchRecords[offset],
                    userId: userId,
                    deviceId: deviceId,
                    scope: scope,
                  );
                }
                if (trackHydration) {
                  await _localStore.addHydrationUnits(batchMutations.length);
                }
                continue;
              } else if (batchResult is BatchWriteConflict) {
                AppLogger.warning(
                  'sync_batch_write_conflict',
                  fields: {
                    'entity': mutation.entity,
                    'code': batchResult.code,
                    'is_pkey': batchResult.isPrimaryKeyConflict,
                    'count': batchMutations.length,
                  },
                );
                if (batchResult.isPrimaryKeyConflict) {
                  for (
                    var offset = 0;
                    offset < batchMutations.length;
                    offset++
                  ) {
                    final item = batchMutations[offset];
                    final rec = batchRecords[offset];
                    await _reconcileBatchCreationReplay(
                      mutation: item,
                      local: rec,
                      userId: userId,
                      deviceId: deviceId,
                      scope: scope,
                    );
                  }
                  if (trackHydration) {
                    await _localStore.addHydrationUnits(batchMutations.length);
                  }
                  continue;
                } else {
                  for (final item in batchMutations) {
                    await _localStore.markMutationFailed(
                      item,
                      'Batch write conflict ${batchResult.code}: ${batchResult.message}',
                    );
                  }
                  continue;
                }
              }
              for (var offset = 0; offset < batchMutations.length; offset++) {
                try {
                  await _pushOne(
                    userId,
                    deviceId,
                    batchMutations[offset],
                    batchRecords[offset],
                    scope: scope,
                  );
                  if (trackHydration) {
                    await _localStore.addHydrationUnits(1);
                  }
                } on _AccountScopeInactive {
                  rethrow;
                } on Object catch (error) {
                  final failure = SupabaseFailure.from(error);
                  await _recordMutationFailure(batchMutations[offset], failure);
                  rethrow;
                }
              }
              continue;
            }
          }
        }
        final record = await _localStore.readMutation(mutation, deviceId);
        if (record == null) {
          // The local row vanished without a delete intent. Never silently
          // discard queued work; surface it for explicit resolution instead.
          await _localStore.markMutationTerminal(
            mutation,
            'The local record for a queued change is missing. '
            'Review or dismiss the change manually.',
          );
          index++;
          continue;
        }
        try {
          await _pushOne(userId, deviceId, mutation, record, scope: scope);
          await _ensureActiveAccountScope(scope);
          if (trackHydration) await _localStore.addHydrationUnits(1);
        } on _AccountScopeInactive {
          rethrow;
        } on Object catch (error) {
          final failure = _canonicalMutationFailure(
            mutation,
            SupabaseFailure.from(error),
          );
          await _recordMutationFailure(mutation, failure);
          throw failure;
        }
        index++;
      }
      if (mutations.length < 200) {
        final remaining = await _localStore.pendingMutations();
        if (remaining.isEmpty) return pushedSomething;
      }
    }
  }

  Future<void> _reconcileBatchCreationReplay({
    required LocalSyncMutation mutation,
    required SyncRecord local,
    required String userId,
    required String deviceId,
    required _ActiveAccountScope scope,
  }) async {
    // A skipped insert or legacy 23505 can be a response-loss replay. It is
    // acknowledged only when the canonical cloud record has the same semantic
    // data. A divergent same-key record remains a durable user-resolvable
    // conflict instead of being overwritten or silently accepted.
    final canonical = await _remoteGateway.fetch(
      spec: local.spec,
      userId: userId,
      deviceId: deviceId,
      recordKey: mutation.recordKey,
    );
    await _ensureActiveAccountScope(scope);
    if (canonical == null) {
      await _localStore.markMutationFailed(
        mutation,
        'A replayed creation had no canonical cloud row; it will be retried.',
      );
      return;
    }
    await _localStore.applyRemoteRecords([canonical]);
    if (_sameRecordData(local, canonical)) {
      await _localStore.markMutationSucceeded(mutation, canonical);
      return;
    }
    await _localStore.markMutationConflicted(
      mutation,
      accountId: userId,
      reason: 'remote_revision_winner',
      localPayloadJson: _localSyncConflictPayload(mutation, local),
      remotePayloadJson: jsonEncode(canonical.values),
      remoteRevision: canonical.revision,
    );
  }

  Future<_MutationPushDisposition> _pushMaintenanceUndo(
    LocalSyncMutation mutation, {
    required String payloadJson,
    required String userId,
    required String deviceId,
    required _ActiveAccountScope scope,
  }) async {
    await _localStore.markMutationInFlight(mutation, userId: userId);
    final result = await _remoteGateway.undoMaintenanceCompletion(
      payloadJson: payloadJson,
      userId: userId,
      deviceId: deviceId,
    );
    await _ensureActiveAccountScope(scope);
    if (result.acknowledged && result.plan != null) {
      await _localStore.markMaintenanceUndoSucceeded(
        mutation,
        plan: result.plan!,
        completionId: mutation.recordKey,
      );
      await _reconcileMaintenanceCompletionReminders(mutation);
      return _MutationPushDisposition.applied;
    }
    if (result.status == MaintenanceUndoStatus.unauthorized) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.permissionDenied,
        message: 'Cloud access was denied.',
      );
    }
    final failure = SupabaseFailure(
      kind: SupabaseFailureKind.conflict,
      message:
          result.conflictReason ??
          'The completion undo could not be reconciled.',
      retryable: result.retryable,
      diagnosticCode: result.status == MaintenanceUndoStatus.invalid
          ? maintenanceCompletionPayloadRejectedCode
          : null,
    );
    if (failure.retryable) throw failure;
    await _recordMutationFailure(mutation, failure);
    return _MutationPushDisposition.terminalHandled;
  }

  Future<_MutationPushDisposition> _pushMaintenanceCompletion(
    LocalSyncMutation mutation, {
    required String payloadJson,
    required String userId,
    required String deviceId,
    required _ActiveAccountScope scope,
  }) async {
    await _localStore.markMutationInFlight(mutation, userId: userId);
    AppLogger.info(
      'sync_maintenance_completion_rpc_sent',
      fields: {
        'operation': _diagnosticId(mutation.operationId),
        'retry': mutation.attempts,
      },
    );

    final result = await _remoteGateway.completeMaintenance(
      payloadJson: payloadJson,
      userId: userId,
      deviceId: deviceId,
    );
    await _ensureActiveAccountScope(scope);

    if (result.status == MaintenanceCompletionStatus.applied ||
        result.status == MaintenanceCompletionStatus.alreadyApplied) {
      if (result.plan != null && result.record != null) {
        if (result.record!.recordKey == mutation.recordKey) {
          await _localStore.markMaintenanceCompletionSucceeded(
            mutation,
            plan: result.plan!,
            record: result.record!,
          );
          await _reconcileMaintenanceCompletionReminders(mutation);
          return _MutationPushDisposition.applied;
        } else {
          // Record ID mismatch -> another device won this occurrence
          await _localStore.reconcileMaintenanceOccurrenceCompletedElsewhere(
            mutation,
            plan: result.plan!,
            record: result.record!,
          );
          return _MutationPushDisposition.applied;
        }
      }
    }

    if (result.status == MaintenanceCompletionStatus.conflict) {
      final reason = result.conflictReason ?? '';
      if (reason == 'occurrence_completed_elsewhere' &&
          result.plan != null &&
          result.record != null) {
        await _localStore.reconcileMaintenanceOccurrenceCompletedElsewhere(
          mutation,
          plan: result.plan!,
          record: result.record!,
        );
        await _reconcileMaintenanceCompletionReminders(mutation);
        return _MutationPushDisposition.applied;
      }

      if (result.plan != null) {
        await _localStore.reconcileRejectedMaintenanceCompletion(
          mutation,
          errorCode: result.conflictReason ?? 'conflict',
          message: _maintenanceConflictMessage(result),
          plan: result.plan,
        );
        await _reconcileMaintenanceCompletionReminders(mutation);
        return _MutationPushDisposition.terminalHandled;
      }
    }

    final message = _maintenanceConflictMessage(result);
    await _localStore.markMaintenanceCompletionFailedVisible(
      mutation,
      errorCode: result.conflictReason ?? result.status.name,
      message: message,
      plan: result.plan,
      record: result.record,
    );
    if (result.plan != null) {
      await _reconcileMaintenanceCompletionReminders(mutation);
    }
    if (result.status == MaintenanceCompletionStatus.invalid) {
      AppLogger.warning(
        maintenanceCompletionPayloadRejectedCode,
        fields: {
          'diagnostic_code': maintenanceCompletionPayloadRejectedCode,
          'sync_entity': mutation.entity,
          'sync_operation': mutation.operation,
          'rpc_status': result.status.name,
          if (result.conflictReason != null)
            'reason_code': result.conflictReason!,
        },
      );
    }
    return _MutationPushDisposition.terminalHandled;
  }

  Future<void> _reconcileMaintenanceCompletionReminders(
    LocalSyncMutation mutation,
  ) async {
    final reconcile = _maintenanceCompletionReminderReconciler;
    if (reconcile == null) return;
    try {
      await reconcile();
      AppLogger.info(
        'sync_maintenance_completion_reminder_reconciled',
        fields: {'operation': _diagnosticId(mutation.operationId)},
      );
    } on Object catch (error) {
      AppLogger.warning(
        'sync_maintenance_completion_reminder_reconciliation_failed',
        error: error,
        fields: {'operation': _diagnosticId(mutation.operationId)},
      );
    }
  }

  String _maintenanceConflictMessage(MaintenanceCompletionResult result) {
    if (result.status == MaintenanceCompletionStatus.invalid) {
      return 'The cloud could not accept this maintenance completion. '
          'Review the task and try again.';
    }
    return switch (result.conflictReason) {
      'occurrence_completed_elsewhere' =>
        'This occurrence was completed on another device. '
            'Your local completion was reconciled with the cloud.',
      'stale_occurrence' =>
        'The maintenance recurrence changed on another device. '
            'Review the task and confirm the completion again.',
      'plan_inactive' =>
        'This maintenance task was disabled or archived on another device.',
      'operation_id_reused' =>
        'This completion identifier is already associated with different data.',
      _ =>
        'The maintenance plan changed on another device. '
            'Review the task and confirm the completion again.',
    };
  }

  Future<void> _recordMutationFailure(
    LocalSyncMutation mutation,
    SupabaseFailure failure,
  ) async {
    if (failure.diagnosticCode == dataApiAclContractMismatchCode) {
      AppLogger.warning(
        dataApiAclContractMismatchCode,
        fields: failure.safeDiagnosticFields(
          entity: mutation.entity,
          operation: mutation.operation,
        ),
      );
    }
    if (failure.retryable) {
      await _localStore.markMutationFailed(
        mutation,
        failure.message,
        errorCode: failure.diagnosticCode,
      );
      return;
    }
    await _localStore.markMutationTerminal(
      mutation,
      failure.message,
      errorCode: failure.diagnosticCode,
    );
  }

  SupabaseFailure _canonicalMutationFailure(
    LocalSyncMutation mutation,
    SupabaseFailure failure,
  ) {
    if (mutation.entity != 'maintenance_completion' ||
        failure.kind != SupabaseFailureKind.conflict ||
        failure.retryable) {
      return failure;
    }
    return SupabaseFailure(
      kind: failure.kind,
      message: _maintenanceConflictMessage(
        const MaintenanceCompletionResult(
          status: MaintenanceCompletionStatus.conflict,
          retryable: false,
        ),
      ),
      retryable: false,
      diagnosticCode: failure.diagnosticCode,
      sqlState: failure.sqlState,
    );
  }

  Future<void> _pushOne(
    String userId,
    String deviceId,
    LocalSyncMutation mutation,
    SyncRecord local, {
    required _ActiveAccountScope scope,
  }) async {
    final shadow = await _localStore.shadow(
      mutation.entity,
      mutation.recordKey,
    );
    var result = await _remoteGateway.write(
      record: local,
      userId: userId,
      deviceId: deviceId,
      expectedRevision: shadow?.remoteRevision,
    );
    await _ensureActiveAccountScope(scope);
    if (!result.conflict) {
      await _completeMutation(userId, mutation, result);
      return;
    }
    final remote = result.canonical;
    final now = DateTime.now().toUtc();
    final localFutureClock =
        remote != null && _isFutureClockSkew(local.clientModifiedAt, now);
    final remoteFutureClock =
        remote != null &&
        remote.serverUpdatedAt != null &&
        _isFutureClockSkew(remote.clientModifiedAt, remote.serverUpdatedAt!);
    if (localFutureClock || remoteFutureClock) {
      _clockSkewConflicts++;
    }
    if (remote != null &&
        ((shadow == null && await _localStore.isUntouchedSeed(local)) ||
            _sameRecordData(local, remote))) {
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (remote == null) {
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: null,
      );
      await _ensureActiveAccountScope(scope);
    } else if (localFutureClock) {
      // A fast local clock must not make an older local edit win solely by
      // timestamp. Keep the server-authoritative revision locally, but the
      // local payload stays durable in the outbox `conflict` state until it
      // is acknowledged or explicitly resolved.
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationConflicted(
        mutation,
        accountId: userId,
        reason: 'remote_clock_skew_winner',
        localPayloadJson: _localSyncConflictPayload(mutation, local),
        remotePayloadJson: jsonEncode(remote.values),
        remoteRevision: remote.revision,
      );
      return;
    } else if (remoteFutureClock) {
      // Conversely, do not let a remote client's future clock dominate a
      // legitimate local mutation. Retry against the server revision once.
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: remote.revision,
      );
      await _ensureActiveAccountScope(scope);
    } else if (local.clientModifiedAt.isAfter(remote.clientModifiedAt) ||
        (local.clientModifiedAt.isAtSameMomentAs(remote.clientModifiedAt) &&
            _localOriginWinsTie(local.originDeviceId, remote.originDeviceId))) {
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: remote.revision,
      );
      await _ensureActiveAccountScope(scope);
    } else {
      // The remote revision/timestamp wins this round. Apply the canonical
      // row locally, but never delete or resolve the local intent: it stays
      // in the outbox `conflict` state across restarts until the exact
      // server acknowledges a newer generation or the user resolves it.
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationConflicted(
        mutation,
        accountId: userId,
        reason: 'remote_revision_winner',
        localPayloadJson: _localSyncConflictPayload(mutation, local),
        remotePayloadJson: jsonEncode(remote.values),
        remoteRevision: remote.revision,
      );
      return;
    }
    if (result.conflict) {
      final entity = mutation.entity.replaceAll('_', ' ');
      throw SupabaseFailure(
        kind: SupabaseFailureKind.conflict,
        message:
            'A cloud $entity record kept changing during synchronization. '
            'The local change remains queued.',
        retryable: true,
      );
    }
    await _ensureActiveAccountScope(scope);
    await _completeMutation(userId, mutation, result);
  }

  String _localSyncConflictPayload(
    LocalSyncMutation mutation,
    SyncRecord local,
  ) {
    return _localStore.encodeConflictPayload(
      operation: mutation.operation,
      values: local.values,
    );
  }

  bool _isFutureClockSkew(DateTime clientTime, DateTime referenceTime) {
    const tolerance = Duration(minutes: 5);
    return clientTime.toUtc().isAfter(referenceTime.toUtc().add(tolerance));
  }

  Future<void> _completeMutation(
    String userId,
    LocalSyncMutation mutation,
    RemoteWriteResult result,
  ) async {
    if (result.cleanupObjectPaths.isEmpty) {
      await _localStore.markMutationSucceeded(mutation, result.canonical);
      return;
    }
    await _localStore.markMutationSucceededAndEnqueueMediaCleanup(
      mutation,
      result.canonical,
      userId: userId,
      objectPaths: result.cleanupObjectPaths,
    );
  }

  Future<void> _processMediaCleanup(
    String userId, {
    required _ActiveAccountScope scope,
    bool trackHydration = false,
  }) async {
    await _ensureActiveAccountScope(scope);
    final localCompleted = await _localStore.processLocalMediaCleanup();
    await _ensureActiveAccountScope(scope);
    if (trackHydration && localCompleted > 0) {
      await _localStore.addHydrationUnits(localCompleted);
    }
    final cleanups = await _localStore.pendingMediaCleanup();
    for (final cleanup in cleanups) {
      await _ensureActiveAccountScope(scope);
      if (cleanup.userId != userId) continue;
      try {
        await _remoteGateway.removeMediaObject(cleanup.objectPath, userId);
        await _ensureActiveAccountScope(scope);
        await _localStore.markMediaCleanupSucceeded(cleanup.objectPath);
        if (trackHydration) await _localStore.addHydrationUnits(1);
      } on _AccountScopeInactive {
        rethrow;
      } on Object catch (error) {
        final failure = SupabaseFailure.from(error);
        if (failure.kind == SupabaseFailureKind.permissionDenied ||
            failure.kind == SupabaseFailureKind.incompatibleSchema) {
          await _localStore.markMediaCleanupTerminal(cleanup, failure.message);
          await _localStore.recordSyncBlocked(failure.message);
          _phaseOverride = SyncPhase.blocked;
          _messageOverride = failure.message;
          throw failure;
        } else {
          await _localStore.markMediaCleanupFailed(cleanup, failure.message);
        }
      }
    }
  }
}

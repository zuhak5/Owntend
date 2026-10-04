part of '../local_sync_store.dart';

/// The local preimage of one authenticated editor commit. It is captured in a
/// short transaction before the RPC; no database lock is held over network I/O.
class AuthoritativeEditorSnapshot {
  const AuthoritativeEditorSnapshot({
    required this.entity,
    required this.recordKey,
    required this.accountId,
    required this.rows,
    required this.outbox,
  });

  final String entity;
  final String recordKey;
  final String accountId;
  final Map<String, List<Map<String, dynamic>>> rows;
  final List<Map<String, dynamic>> outbox;
}

const _editorDetailEntities = {
  'device_detail',
  'pet_detail',
  'plant_detail',
  'safety_detail',
};

mixin _LocalSyncEditorMutationStore on _LocalSyncStoreBase {
  Future<AuthoritativeEditorSnapshot> captureAuthoritativeEditor({
    required String entity,
    required String recordKey,
    required String accountId,
    required DateTime expectedUpdatedAt,
    String? expectedOccurrenceId,
  }) => db.transaction(() async {
    if (entity != 'asset' && entity != 'maintenance_plan') {
      throw ArgumentError.value(entity, 'entity');
    }
    await _checkEditorAccount(accountId);
    final rows = await _readEditorRows(entity, recordKey);
    final spec = syncSpecByEntity[entity]!;
    final root = rows[entity]!.singleOrNull;
    if (root == null ||
        root['updated_at'] !=
            _toLocalValue(spec, 'updated_at', expectedUpdatedAt) ||
        (expectedOccurrenceId != null &&
            root['current_occurrence_id'] != expectedOccurrenceId)) {
      throw StateError('The record changed while this editor was open.');
    }
    return AuthoritativeEditorSnapshot(
      entity: entity,
      recordKey: recordKey,
      accountId: accountId,
      rows: rows,
      outbox: await _readEditorOutbox(entity, recordKey),
    );
  });

  /// Rebase only the mutation acknowledged by this RPC. The ordinary repository
  /// save runs in this same transaction and still enforces its CAS precondition.
  Future<void> finishAuthoritativeEditor({
    required AuthoritativeEditorSnapshot snapshot,
    required Map<String, dynamic> canonicalJson,
    required String expectedTarget,
    required Future<void> Function(DateTime expectedUpdatedAt) saveLocalEdit,
    List<Map<String, dynamic>> detailRows = const [],
    required bool Function() accountIsCurrent,
  }) async {
    final spec = syncSpecByEntity[snapshot.entity]!;
    final canonical = _editorCanonical(spec, canonicalJson, snapshot);
    final targetColumn = snapshot.entity == 'asset' ? 'asset_type' : 'asset_id';
    final expectedRoot = _editorLocalValues(spec, canonical.values);
    final originalRoot = snapshot.rows[snapshot.entity]!.single;
    if (expectedRoot[targetColumn] != expectedTarget ||
        !_sameEditorRow(
          originalRoot,
          expectedRoot,
          except: {targetColumn, 'updated_at'},
        )) {
      throw StateError('The server record includes another edit.');
    }
    final details = <String, SyncRecord>{};
    for (final envelope in detailRows) {
      final entity = envelope['entity'];
      final row = envelope['row'];
      if (entity is! String ||
          !_editorDetailEntities.contains(entity) ||
          row is! Map ||
          details.containsKey(entity)) {
        throw const FormatException('Invalid authoritative detail envelope.');
      }
      details[entity] = _editorCanonical(
        syncSpecByEntity[entity]!,
        Map<String, dynamic>.from(row),
        snapshot,
      );
    }
    if (snapshot.entity == 'asset') {
      final expectedDetail = expectedTarget == 'general'
          ? null
          : '${expectedTarget}_detail';
      if (details.length != (expectedDetail == null ? 0 : 1) ||
          (expectedDetail != null && !details.containsKey(expectedDetail))) {
        throw const FormatException(
          'The type change omitted canonical details.',
        );
      }
    } else if (details.isNotEmpty) {
      throw const FormatException('A task move returned item details.');
    }

    await db.transaction(() async {
      if (!accountIsCurrent()) throw StateError('The editor account changed.');
      await _checkEditorAccount(snapshot.accountId);
      final live = await _readEditorRows(snapshot.entity, snapshot.recordKey);
      final currentOutbox = await _readEditorOutbox(
        snapshot.entity,
        snapshot.recordKey,
      );
      // A successful background push may acknowledge pre-existing intent during
      // the RPC. New or replaced intent must still block the rebase.
      if (currentOutbox.any(
        (row) =>
            !snapshot.outbox.any((original) => _sameEditorRow(row, original)),
      )) {
        throw StateError('New local work must be preserved.');
      }
      for (final entry in live.entries) {
        final original = snapshot.rows[entry.key]!;
        final acknowledged = entry.key == snapshot.entity
            ? [expectedRoot]
            : _editorDetailEntities.contains(entry.key)
            ? [
                if (details[entry.key] case final record?)
                  _editorLocalValues(record.spec, record.values),
              ]
            : null;
        if (!_sameEditorRows(entry.value, original) &&
            (acknowledged == null ||
                !_sameEditorRows(entry.value, acknowledged))) {
          throw StateError('A newer local record must be preserved.');
        }
      }
      for (final record in [canonical, ...details.values]) {
        final shadow =
            await (db.select(db.syncShadows)..where(
                  (row) =>
                      row.entity.equals(record.spec.entity) &
                      row.recordKey.equals(record.recordKey),
                ))
                .getSingleOrNull();
        if (shadow != null && shadow.remoteRevision > record.revision!) {
          throw StateError('A newer server revision must be preserved.');
        }
      }
      await withOutboxSuppressed(() async {
        await _upsertLocal(canonical);
        await _saveShadow(canonical);
        if (snapshot.entity == 'asset') {
          for (final entity in _editorDetailEntities) {
            final detail = details[entity];
            if (detail != null) {
              await _upsertLocal(detail);
              await _saveShadow(detail);
            } else {
              final detailSpec = syncSpecByEntity[entity]!;
              await db.customUpdate(
                'DELETE FROM ${detailSpec.localTable} WHERE asset_id = ?',
                variables: [Variable(snapshot.recordKey)],
                updates: {
                  db.allTables.firstWhere(
                    (t) => t.actualTableName == detailSpec.localTable,
                  ),
                },
                updateKind: UpdateKind.delete,
              );
              await (db.delete(db.syncShadows)..where(
                    (row) =>
                        row.entity.equals(entity) &
                        row.recordKey.equals(snapshot.recordKey),
                  ))
                  .go();
            }
          }
        }
      });
      if (snapshot.entity == 'asset') {
        // The accepted type RPC replaced this complete detail set. Only its
        // unchanged pre-RPC intents are acknowledged; unrelated work was checked
        // above and is never removed here.
        await (db.delete(db.syncOutbox)..where(
              (row) =>
                  row.entity.isIn(_editorDetailEntities) &
                  row.recordKey.equals(snapshot.recordKey),
            ))
            .go();
      }
      if (!accountIsCurrent()) throw StateError('The editor account changed.');
      await saveLocalEdit(_dateTimeFromStorage(expectedRoot['updated_at'])!);
      if (!accountIsCurrent()) throw StateError('The editor account changed.');
    });
  }

  Future<void> _checkEditorAccount(String accountId) async {
    final current = await account();
    if (current.boundUserId != accountId ||
        current.restorePending ||
        current.blockedReason != null) {
      throw StateError('The editor belongs to another local account.');
    }
  }

  SyncRecord _editorCanonical(
    SyncEntitySpec spec,
    Map<String, dynamic> json,
    AuthoritativeEditorSnapshot snapshot,
  ) {
    if (json['user_id'] != snapshot.accountId ||
        json['revision'] is! int ||
        (json['revision'] as int) < 1 ||
        json['updated_at'] is! String) {
      throw const FormatException('Invalid authoritative editor identity.');
    }
    final record = SyncRecord.fromRemote(spec, json);
    if (record.recordKey != snapshot.recordKey || record.isDeleted) {
      throw const FormatException('Invalid authoritative editor record.');
    }
    return record;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _readEditorRows(
    String entity,
    String id,
  ) async {
    final entities = [
      entity,
      if (entity == 'asset')
        ..._editorDetailEntities
      else
        'maintenance_plan_metadata',
    ];
    final rows = <String, List<Map<String, dynamic>>>{};
    for (final name in entities) {
      final spec = syncSpecByEntity[name]!;
      rows[name] = [
        for (final row
            in await db
                .customSelect(
                  'SELECT ${spec.localColumns.join(', ')} FROM ${spec.localTable} WHERE ${spec.keyColumns.single} = ?',
                  variables: [Variable(id)],
                )
                .get())
          Map<String, dynamic>.from(row.data),
      ];
    }
    if (entity == 'asset') {
      rows['tags'] = [
        for (final row
            in await db
                .customSelect(
                  'SELECT t.id, t.name FROM asset_tags a JOIN tags t ON t.id = a.tag_id WHERE a.asset_id = ? ORDER BY t.id',
                  variables: [Variable(id)],
                )
                .get())
          Map<String, dynamic>.from(row.data),
      ];
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _readEditorOutbox(
    String entity,
    String id,
  ) async {
    final related = entity == 'asset'
        ? ['asset', ..._editorDetailEntities]
        : ['maintenance_plan', 'maintenance_plan_metadata'];
    return [
      for (final row
          in await db
              .customSelect(
                'SELECT entity, record_key, operation, generation, local_sequence, payload_json FROM ${db.syncOutbox.actualTableName} '
                'WHERE (record_key = ? AND entity IN (${related.map((_) => '?').join(',')})) '
                "OR (? = 'asset' AND entity = 'asset_tag' AND substr(record_key, 1, ?) = ?) ORDER BY entity, record_key",
                variables: [
                  Variable(id),
                  for (final name in related) Variable(name),
                  Variable(entity),
                  Variable(id.length + 1),
                  Variable('$id|'),
                ],
              )
              .get())
        Map<String, dynamic>.from(row.data),
    ];
  }
}

Map<String, dynamic> _editorLocalValues(
  SyncEntitySpec spec,
  Map<String, dynamic> values,
) => {
  for (final column in spec.localColumns)
    column: _toLocalValue(spec, column, values[column]),
};

bool _sameEditorRow(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  Set<String> except = const {},
}) =>
    a.length == b.length &&
    a.keys.every(
      (key) => except.contains(key) || jsonEncode(a[key]) == jsonEncode(b[key]),
    );

bool _sameEditorRows(
  List<Map<String, dynamic>> a,
  List<Map<String, dynamic>> b,
) =>
    a.length == b.length &&
    List.generate(
      a.length,
      (index) => index,
    ).every((index) => _sameEditorRow(a[index], b[index]));

import '../supabase/supabase_failure.dart';
import 'sync_dtos.dart';

const syncFeedContractVersion = 1;
const _syncFeedOperations = {'INSERT', 'UPDATE', 'DELETE'};

class ChangeFeedEntry {
  const ChangeFeedEntry({
    required this.changeSeq,
    required this.record,
    required this.operation,
  });

  final int changeSeq;
  final SyncRecord record;
  final String operation;
}

void requireSyncFeedContractVersion(Object? version) {
  if (version != syncFeedContractVersion) {
    throw syncFeedProtocolFailure();
  }
}

SyncEntitySpec syncFeedSpecForEntity(String entity) {
  final spec = syncSpecByEntity[entity];
  if (spec == null) {
    throw syncFeedProtocolFailure();
  }
  return spec;
}

ChangeFeedEntry parseSyncFeedChange(Map<String, dynamic> change) {
  requireSyncFeedContractVersion(change['contract_version']);
  final changeSeq = change['change_seq'];
  final entity = change['entity_type'];
  final operation = change['op_type'];
  final rawKeyData = change['key_data'];
  final rawRecordId = change['record_id'];
  final rawRevision = change['revision'];
  final serverCreatedAt = _parseRequiredUtc(change['created_at']);
  final rawClientUpdatedAt = change['client_updated_at'];
  final clientUpdatedAt = rawClientUpdatedAt == null
      ? serverCreatedAt
      : _parseRequiredUtc(rawClientUpdatedAt);
  if (changeSeq is! int ||
      changeSeq <= 0 ||
      entity is! String ||
      operation is! String ||
      !_syncFeedOperations.contains(operation) ||
      rawKeyData is! Map ||
      rawRecordId is! String ||
      rawRevision is! int ||
      rawRevision < 1) {
    throw syncFeedProtocolFailure();
  }

  final spec = syncFeedSpecForEntity(entity);
  late final Map<String, dynamic> keyData;
  try {
    keyData = Map<String, dynamic>.from(rawKeyData);
  } on Object {
    throw syncFeedProtocolFailure();
  }
  final expectedKeys = spec.keyColumns.toSet();
  final actualKeys = keyData.keys.toSet();
  if (actualKeys.length != expectedKeys.length ||
      !actualKeys.containsAll(expectedKeys)) {
    throw syncFeedProtocolFailure();
  }

  final keyValues = <String, dynamic>{};
  for (final column in spec.keyColumns) {
    final value = keyData[column];
    if (value is! String || value.isEmpty) {
      throw syncFeedProtocolFailure();
    }
    keyValues[column] = value;
  }
  final recordKey = spec.keyColumns.isEmpty
      ? spec.entity
      : spec.keyColumns.map((column) => keyValues[column]).join('|');
  if (rawRecordId != recordKey) {
    throw syncFeedProtocolFailure();
  }

  late final SyncRecord record;
  if (operation == 'DELETE') {
    if (change['payload'] != null) {
      throw syncFeedProtocolFailure();
    }
    record = SyncRecord(
      spec: spec,
      recordKey: recordKey,
      values: Map.unmodifiable(keyValues),
      clientModifiedAt: clientUpdatedAt,
      revision: rawRevision,
      serverUpdatedAt: serverCreatedAt,
      deletedAt: serverCreatedAt,
    );
  } else {
    final rawPayload = change['payload'];
    if (rawPayload is! Map) {
      throw syncFeedProtocolFailure();
    }
    late final Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(rawPayload);
    } on Object {
      throw syncFeedProtocolFailure();
    }
    if (!spec.remoteSelectColumns.every(payload.containsKey) ||
        payload['revision'] != rawRevision) {
      throw syncFeedProtocolFailure();
    }
    for (final entry in keyValues.entries) {
      if (payload[spec.remoteColumnFor(entry.key)] != entry.value) {
        throw syncFeedProtocolFailure();
      }
    }
    try {
      final canonical = SyncRecord.fromRemote(spec, payload);
      if (canonical.recordKey != recordKey) {
        throw syncFeedProtocolFailure();
      }
      record = SyncRecord(
        spec: canonical.spec,
        recordKey: canonical.recordKey,
        values: canonical.values,
        clientModifiedAt: canonical.clientModifiedAt,
        originDeviceId: canonical.originDeviceId,
        revision: rawRevision,
        serverUpdatedAt: canonical.serverUpdatedAt ?? serverCreatedAt,
        deletedAt: canonical.deletedAt,
      );
    } on SupabaseFailure {
      rethrow;
    } on Object {
      throw syncFeedProtocolFailure();
    }
  }

  return ChangeFeedEntry(
    changeSeq: changeSeq,
    record: record,
    operation: operation,
  );
}

DateTime _parseRequiredUtc(Object? value) {
  if (value is! String) {
    throw syncFeedProtocolFailure();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw syncFeedProtocolFailure();
  }
  return parsed.toUtc();
}

SupabaseFailure syncFeedProtocolFailure() {
  return const SupabaseFailure(
    kind: SupabaseFailureKind.incompatibleSchema,
    message:
        'This Owntend build is not compatible with the cloud sync protocol. '
        'Install the latest release.',
  );
}

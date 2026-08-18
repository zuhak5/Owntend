import '../supabase/supabase_failure.dart';
import 'sync_dtos.dart';

const syncFeedContractVersion = '1.0.0';
const _syncFeedOperations = {'INSERT', 'UPDATE', 'DELETE'};

class ParsedSyncFeedChange {
  const ParsedSyncFeedChange({
    required this.spec,
    required this.recordKey,
    required this.operation,
    required this.keyValues,
  });

  final SyncEntitySpec spec;
  final String recordKey;
  final String operation;
  final Map<String, dynamic> keyValues;
}

void requireSyncFeedContractVersion(String version) {
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

ParsedSyncFeedChange parseSyncFeedChange(Map<String, dynamic> change) {
  final entity = change['entity_type'];
  final operation = change['op_type'];
  final rawKeyData = change['key_data'];
  final rawRecordId = change['record_id'];
  if (entity is! String ||
      operation is! String ||
      !_syncFeedOperations.contains(operation) ||
      rawKeyData is! Map ||
      rawRecordId is! String) {
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

  return ParsedSyncFeedChange(
    spec: spec,
    recordKey: recordKey,
    operation: operation,
    keyValues: Map.unmodifiable(keyValues),
  );
}

SupabaseFailure syncFeedProtocolFailure() {
  return const SupabaseFailure(
    kind: SupabaseFailureKind.incompatibleSchema,
    message:
        'This Owntend build is not compatible with the cloud sync protocol. '
        'Install the latest release.',
  );
}

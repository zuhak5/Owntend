import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum SidecarType { restoreStaged, previousBackup }

enum SidecarState { active, pendingCleanup, cleaned }

@immutable
class SidecarEntry {
  const SidecarEntry({
    required this.token,
    required this.type,
    required this.canonicalRoot,
    required this.activeJournalId,
    required this.createdAt,
    this.state = SidecarState.active,
    this.lastError,
  });

  final String token;
  final SidecarType type;
  final String canonicalRoot;
  final String activeJournalId;
  final DateTime createdAt;
  final SidecarState state;
  final String? lastError;

  String get relativeName {
    final prefix = type == SidecarType.restoreStaged ? 'restore' : 'previous';
    return '$canonicalRoot.$prefix-$token';
  }

  String get id => '$canonicalRoot:$type:$token';

  Map<String, dynamic> toJson() => {
    'token': token,
    'type': type.name,
    'canonicalRoot': canonicalRoot,
    'activeJournalId': activeJournalId,
    'createdAt': createdAt.toIso8601String(),
    'state': state.name,
    if (lastError != null) 'lastError': lastError,
  };

  factory SidecarEntry.fromJson(Map<String, dynamic> json) => SidecarEntry(
    token: json['token'] as String,
    type: SidecarType.values.byName(json['type'] as String),
    canonicalRoot: json['canonicalRoot'] as String,
    activeJournalId: json['activeJournalId'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    state: SidecarState.values.byName(json['state'] as String? ?? 'active'),
    lastError: json['lastError'] as String?,
  );

  SidecarEntry copyWith({SidecarState? state, String? lastError}) =>
      SidecarEntry(
        token: token,
        type: type,
        canonicalRoot: canonicalRoot,
        activeJournalId: activeJournalId,
        createdAt: createdAt,
        state: state ?? this.state,
        lastError: lastError,
      );
}

class SidecarRegistryStore {
  SidecarRegistryStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'owntend_sidecar_registry_v1';
  static final sidecarPattern = RegExp(
    r'^(photos|profile|cloud_media)\.(restore|previous)-([a-zA-Z0-9_-]+)$',
  );

  final FlutterSecureStorage _storage;

  Future<List<SidecarEntry>> readAll() async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SidecarEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<SidecarEntry> entries) async {
    final json = entries.map((e) => e.toJson()).toList();
    await _storage.write(key: key, value: jsonEncode(json));
  }

  Future<void> registerSidecar(SidecarEntry entry) async {
    final current = await readAll();
    final updated = current.where((e) => e.id != entry.id).toList()..add(entry);
    await saveAll(updated);
  }

  Future<void> updateSidecarState(
    String token,
    String canonicalRoot,
    SidecarType type,
    SidecarState state, {
    String? error,
  }) async {
    final targetId = '$canonicalRoot:$type:$token';
    final current = await readAll();
    final updated = current.map((e) {
      if (e.id == targetId) {
        return e.copyWith(state: state, lastError: error);
      }
      return e;
    }).toList();
    await saveAll(updated);
  }

  Future<void> removeEntry(
    String token,
    String canonicalRoot,
    SidecarType type,
  ) async {
    final targetId = '$canonicalRoot:$type:$token';
    final current = await readAll();
    final updated = current.where((e) => e.id != targetId).toList();
    await saveAll(updated);
  }

  Future<void> clearAll() async {
    await _storage.delete(key: key);
  }

  /// Discovers all sidecar directories under [appDir] matching exact pattern.
  Future<List<Directory>> discoverSidecars(Directory appDir) async {
    if (!await appDir.exists()) return const [];
    final results = <Directory>[];
    await for (final entity in appDir.list(followLinks: false)) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        if (sidecarPattern.hasMatch(name)) {
          if (_isPathSafeAndContained(appDir, entity.path)) {
            results.add(entity);
          }
        }
      }
    }
    return results;
  }

  /// Safely sweeps orphans under [appDir].
  /// Preserves entries linked to active journals or active tokens.
  Future<void> sweepOrphans({
    required Directory appDir,
    Set<String> activeJournalIds = const {},
    Set<String> activeRestoreTokens = const {},
  }) async {
    final registered = await readAll();
    final discovered = await discoverSidecars(appDir);
    final nextRegistry = <SidecarEntry>[];

    // Build map of registered entries by relative name
    final regByName = <String, SidecarEntry>{
      for (final entry in registered) entry.relativeName: entry,
    };

    for (final dir in discovered) {
      final name = p.basename(dir.path);
      final match = sidecarPattern.firstMatch(name);
      if (match == null) continue;
      final root = match.group(1)!;
      final typeStr = match.group(2)!;
      final token = match.group(3)!;
      final type = typeStr == 'restore'
          ? SidecarType.restoreStaged
          : SidecarType.previousBackup;

      // Protection checks:
      if (activeRestoreTokens.contains(token)) {
        // Active restore in progress, preserve
        if (regByName.containsKey(name)) {
          nextRegistry.add(regByName[name]!);
        }
        continue;
      }

      final regEntry = regByName[name];
      if (regEntry != null &&
          activeJournalIds.contains(regEntry.activeJournalId)) {
        // Linked to active restore journal, preserve
        nextRegistry.add(regEntry);
        continue;
      }

      // Safe to attempt sweep
      try {
        if (FileSystemEntity.isLinkSync(dir.path)) {
          // Reject symlink deletion for security
          if (regEntry != null) {
            nextRegistry.add(
              regEntry.copyWith(
                state: SidecarState.pendingCleanup,
                lastError: 'Symlink detected, deletion refused for safety',
              ),
            );
          }
          continue;
        }
        await dir.delete(recursive: true);
      } catch (e) {
        if (regEntry != null) {
          nextRegistry.add(
            regEntry.copyWith(
              state: SidecarState.pendingCleanup,
              lastError: e.toString(),
            ),
          );
        } else {
          nextRegistry.add(
            SidecarEntry(
              token: token,
              type: type,
              canonicalRoot: root,
              activeJournalId: '',
              createdAt: DateTime.now().toUtc(),
              state: SidecarState.pendingCleanup,
              lastError: e.toString(),
            ),
          );
        }
      }
    }

    await saveAll(nextRegistry);
  }

  static bool _isPathSafeAndContained(Directory parent, String childPath) {
    final normParent = p.normalize(parent.path);
    final normChild = p.normalize(childPath);
    if (!p.isWithin(normParent, normChild)) return false;
    if (FileSystemEntity.isLinkSync(normChild)) return false;
    return true;
  }
}

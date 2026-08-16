part of 'repositories.dart';

class DriftNotificationInboxRepository implements NotificationInboxRepository {
  DriftNotificationInboxRepository(this.db);

  final AppDatabase db;

  @override
  Stream<List<domain.InboxNotification>> watchNotifications() {
    final query = db.select(db.inboxNotifications)
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.watch().map((rows) => rows.map(_inboxFromRow).toList());
  }

  @override
  Stream<int> watchUnreadCount() {
    final query = db.select(db.inboxNotifications)
      ..where((row) => row.readAt.isNull());
    return query.watch().map((rows) => rows.length).distinct();
  }

  @override
  Future<List<domain.InboxNotification>> listNotifications() async {
    final rows = await (db.select(
      db.inboxNotifications,
    )..orderBy([(row) => OrderingTerm.desc(row.createdAt)])).get();
    return rows.map(_inboxFromRow).toList();
  }

  @override
  Future<int> unreadCount() async {
    final rows = await (db.select(
      db.inboxNotifications,
    )..where((row) => row.readAt.isNull())).get();
    return rows.length;
  }

  @override
  Future<void> clear() async {
    await db.delete(db.inboxNotifications).go();
  }

  @override
  Future<void> createNotification({
    required String title,
    required String body,
    required String kind,
    String? route,
    String? planId,
    domain.NotificationMessageCode? messageCode,
    Map<String, dynamic> messageArgs = const {},
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty && cleanBody.isEmpty) {
      return;
    }
    final normalizedKind = _blankToNull(kind)?.toLowerCase() ?? 'general';
    final routeValue = _blankToNull(route);
    final planValue = _blankToNull(planId);
    final now = DateTime.now();
    final dedupeKey = _notificationDedupeKey(
      kind: normalizedKind,
      title: cleanTitle,
      body: cleanBody,
      route: routeValue,
      planId: planValue,
      createdAt: now,
    );
    final cutoff = now.subtract(_notificationDedupeWindow(normalizedKind));
    final duplicateQuery = db.select(db.inboxNotifications)
      ..where((row) {
        var predicate =
            row.kind.equals(normalizedKind) &
            row.title.equals(cleanTitle) &
            row.createdAt.isBiggerOrEqualValue(cutoff);
        if (_notificationDedupeIncludesBody(normalizedKind)) {
          predicate = predicate & row.body.equals(cleanBody);
        }
        predicate =
            predicate &
            (routeValue == null
                ? row.route.isNull()
                : row.route.equals(routeValue));
        predicate =
            predicate &
            (planValue == null
                ? row.planId.isNull()
                : row.planId.equals(planValue));
        return predicate;
      })
      ..limit(1);
    final duplicate = await duplicateQuery.getSingleOrNull();
    if (duplicate != null) {
      final contentChanged =
          duplicate.body != cleanBody ||
          duplicate.messageCode != messageCode?.wireValue ||
          duplicate.messageArgs != jsonEncode(messageArgs);
      final shouldReopen =
          normalizedKind == 'task' && duplicate.readAt != null ||
          normalizedKind == 'digest' && contentChanged;
      if (contentChanged || shouldReopen) {
        await (db.update(
          db.inboxNotifications,
        )..where((row) => row.id.equals(duplicate.id))).write(
          InboxNotificationsCompanion(
            title: Value(cleanTitle.isEmpty ? 'Owntend update' : cleanTitle),
            body: Value(cleanBody),
            messageCode: Value(messageCode?.wireValue),
            messageArgs: Value(jsonEncode(messageArgs)),
            readAt: shouldReopen ? const Value(null) : Value(duplicate.readAt),
            updatedAt: Value(now),
          ),
        );
      }
      return;
    }
    await db
        .into(db.inboxNotifications)
        .insert(
          InboxNotificationsCompanion.insert(
            id: dedupeKey,
            title: cleanTitle.isEmpty ? 'Owntend update' : cleanTitle,
            body: cleanBody,
            kind: normalizedKind,
            route: Value(routeValue),
            planId: Value(planValue),
            messageCode: Value(messageCode?.wireValue),
            messageArgs: Value(jsonEncode(messageArgs)),
            dedupeKey: Value(dedupeKey),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await db.customStatement('''
DELETE FROM notification_inbox
WHERE id NOT IN (
  SELECT id
  FROM notification_inbox
  ORDER BY created_at DESC
  LIMIT 250
)
''');
  }

  @override
  Future<void> markRead(String id) async {
    await (db.update(
      db.inboxNotifications,
    )..where((row) => row.id.equals(id))).write(
      InboxNotificationsCompanion(
        readAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> markAllRead() async {
    await (db.update(
      db.inboxNotifications,
    )..where((row) => row.readAt.isNull())).write(
      InboxNotificationsCompanion(
        readAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

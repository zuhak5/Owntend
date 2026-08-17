from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"missing analyzer-fixup block in {path}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "lib/src/core/services/notification_service.dart",
    "@visibleForTesting\nbool notificationBackgroundAccountMatches({",
    "bool notificationBackgroundAccountMatches({",
)

path = Path("lib/src/core/services/reminder_schedule_reconciler.dart")
text = path.read_text()
old_constructor = """  NotificationReconciliationConsumer({
    required AppDatabase database,
    required NotificationScheduler scheduler,
    required NotificationReconciliationAccountGuard accountGuard,
    DateTime Function()? now,
  }) : _database = database,
       _scheduler = scheduler,
       _accountGuard = accountGuard,
       _now = now ?? DateTime.now;

  static const _maxRetryDelay = Duration(hours: 1);

  final AppDatabase _database;
  final NotificationScheduler _scheduler;
  final NotificationReconciliationAccountGuard _accountGuard;
"""
new_constructor = """  NotificationReconciliationConsumer({
    required this.database,
    required this.scheduler,
    required this.accountGuard,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _maxRetryDelay = Duration(hours: 1);

  final AppDatabase database;
  final NotificationScheduler scheduler;
  final NotificationReconciliationAccountGuard accountGuard;
"""
if old_constructor not in text:
    raise SystemExit("missing consumer constructor block")
text = text.replace(old_constructor, new_constructor, 1)
text = text.replace("_database.", "database.")
text = text.replace("_scheduler.", "scheduler.")
text = text.replace("_accountGuard(", "accountGuard(")
path.write_text(text)

replace_once(
    "lib/src/features/startup/presentation/startup_restoration_screen.dart",
    """      if (scheduler is NotificationBackgroundRegistration) {
        await scheduler.registerBackgroundRefresh();
      }
""",
    """      if (scheduler is NotificationBackgroundRegistration) {
        final backgroundRegistration =
            scheduler as NotificationBackgroundRegistration;
        await backgroundRegistration.registerBackgroundRefresh();
      }
""",
)

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one old match, found {count}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


# An exact causal Undo is the authoritative compensation. It must be pushed before
# generic plan/record guard mutations created by the same local Undo transaction.
replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """    mutations.sort((a, b) {\n      final aDelete = a.operation == 'delete';\n      final bDelete = b.operation == 'delete';\n      if (aDelete != bDelete) {\n        return aDelete ? -1 : 1;\n      }\n\n      final aOrder = dependencyOrder[a.entity] ?? dependencyOrder.length;""",
    """    mutations.sort((a, b) {\n      if (a.entity == 'maintenance_undo' &&\n          b.entity != 'maintenance_undo') {\n        return -1;\n      }\n      if (b.entity == 'maintenance_undo' &&\n          a.entity != 'maintenance_undo') {\n        return 1;\n      }\n\n      final aDelete = a.operation == 'delete';\n      final bDelete = b.operation == 'delete';\n      if (aDelete != bDelete) {\n        return aDelete ? -1 : 1;\n      }\n\n      final aOrder = dependencyOrder[a.entity] ?? dependencyOrder.length;""",
)
replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """      if (a.entity == b.entity) return 0;\n      if (a.entity == 'maintenance_undo') return -1;\n      if (b.entity == 'maintenance_undo') return 1;\n      if (a.entity == 'maintenance_completion') return -1;""",
    """      if (a.entity == b.entity) return 0;\n      if (a.entity == 'maintenance_completion') return -1;""",
)

# Exercise the queue ordering while the completion RPC is still blocked. Generic
# record/plan guards should exist, but the atomic Undo must be the first ready mutation.
replace_once(
    "test/sync_coordinator_test.dart",
    """      await repo.undoCompletion(\n        planId: 'maintenance-plan-undo-race',\n        completionId: completion.operationId!,\n        previousDueDate: completion.previousDueDate!,\n        expectedCurrentNextDueDate: completion.nextDueDate!,\n      );\n      gateway.maintenanceCompletionGate!.complete();""",
    """      await repo.undoCompletion(\n        planId: 'maintenance-plan-undo-race',\n        completionId: completion.operationId!,\n        previousDueDate: completion.previousDueDate!,\n        expectedCurrentNextDueDate: completion.nextDueDate!,\n      );\n      final queuedAfterUndo = await store.pendingMutations();\n      expect(queuedAfterUndo.first.entity, 'maintenance_undo');\n      expect(\n        queuedAfterUndo.any(\n          (mutation) =>\n              mutation.entity == 'maintenance_record' &&\n              mutation.operation == 'delete',\n        ),\n        isTrue,\n      );\n      gateway.maintenanceCompletionGate!.complete();""",
)

print("phase12 undo outbox priority repair applied")

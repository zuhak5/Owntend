from pathlib import Path

path = Path('test/bug_010_bug_014_notification_consumers_test.dart')
text = path.read_text()
replacements = {
    "expect(bootstrap, contains('await scheduler.registerBackgroundRefresh();'));": "expect(\n        bootstrap,\n        contains('await backgroundRegistration.registerBackgroundRefresh();'),\n      );",
    "expect(request.nextAttemptAt, now.add(const Duration(minutes: 1)));": "expect(\n        request.nextAttemptAt?.toUtc(),\n        now.add(const Duration(minutes: 1)),\n      );",
    "expect(request.updatedAt, newer);": "expect(request.updatedAt.toUtc(), newer);",
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'missing test-fixup block: {old}')
    text = text.replace(old, new, 1)
path.write_text(text)

from pathlib import Path

path = Path('test/widget_test.dart')
text = path.read_text(encoding='utf-8')
old = "    expect(find.text('Fish in Kitchen'), findsWidgets);"
new = "    expect(find.text('Fish · Kitchen'), findsWidgets);"
if text.count(old) != 1:
    raise SystemExit(f'expected one legacy location assertion, found {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Updated task location expectation.')

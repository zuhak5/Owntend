from pathlib import Path

path = Path('tool/agent_remediation.py')
text = path.read_text(encoding='utf-8')

fish_helper = """String _fishBreedLabel(BuildContext context, String value) =>
    _fishTypeOptions.contains(value) ? _fishTypeLabel(context, value) : value;

"""
if text.count(fish_helper) != 1:
    raise SystemExit(f'fish helper guard changed unexpectedly: {text.count(fish_helper)}')
text = text.replace(fish_helper, '', 1)

target = r'''    "select extensions.is(\n  (\n    public.create_task_with_point_debit(",'''
replacement = r'''    "select extensions.is(\n  (\n    public.create_task_with_point_debit(\n      jsonb_build_object(\n        'operation_id', '44444444-0000-0000-0000-000000000002',",'''
if text.count(target) != 1:
    raise SystemExit(f'expected one SQL anchor declaration, found {text.count(target)}')
text = text.replace(target, replacement, 1)

path.write_text(text, encoding='utf-8')
print('Remediation patcher guards updated.')

import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';

class CompleteTaskDialog extends StatefulWidget {
  const CompleteTaskDialog({required this.task, super.key});

  final TaskItem task;

  @override
  State<CompleteTaskDialog> createState() => _CompleteTaskDialogState();
}

class _CompleteTaskDialogState extends State<CompleteTaskDialog> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EditorSheetFrame(
      title: context.l10n.completeTaskTitleCase,
      saveLabel: context.l10n.completeAction,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => Navigator.of(context).pop(_notesController.text),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hk_ui.PremiumCard(
            padding: const EdgeInsets.all(14),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              '${widget.task.plan.title} - ${widget.task.asset.name}',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
          const SizedBox(height: HkSpacing.sm),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.l10n.completionNotes,
              hintText:
                  context.l10n.whatChangedWhatWasReplacedOrWhatNeedsFollowUp,
            ),
          ),
        ],
      ),
    );
  }
}

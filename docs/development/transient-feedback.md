# Transient feedback and Undo

## Purpose

Owntend routes application SnackBars through `FeedbackCoordinator` in
`lib/src/ui/feedback/feedback_coordinator.dart`. The `showToast`,
`showUndoToast`, and Trash helpers in `lib/src/ui/components.dart` are adapters;
feature code should not call `ScaffoldMessenger.showSnackBar` directly.

The coordinator owns one active item and a pending queue. This keeps feedback
consistent across screens and, more importantly, prevents a passive message or
error from erasing an Undo opportunity.

## Ordering contract

- An active Undo item is protected. Passive, actionable, warning, error, and
  destructive items wait behind it.
- Undo items batch only when their non-null batch keys are exactly equal.
  Trash uses `trash`; maintenance completion uses `completion`, so those
  operations never merge.
- A compatible batch updates the visible count and starts a fresh five-second
  opportunity.
- Batch Undo callbacks run newest first (LIFO). Finalization callbacks run
  oldest first. Every action is guarded against double taps.
- A failing callback is logged as a scrubbed technical event and does not
  strand later callbacks or queued feedback.
- With accessible navigation enabled, Flutter's persistent action behavior
  keeps an Undo bar available until the user acts or dismisses it. Other users
  receive the fixed five-second Undo interval.

Task, item, room, and area moves to Trash all provide restoration through this
contract. Maintenance-completion Undo uses a separate aggregation key and
continues to reconcile streak and reminder state. Permanent deletion from the
Trash screen is confirmed separately and intentionally has no Undo action.

## Layout and localization

SnackBars use floating placement with a directional 16-dp horizontal margin
and a 12-dp visual gap. Flutter's `Scaffold` owns vertical collision avoidance
for the actual bottom navigation, persistent footer, floating action button,
safe area, and keyboard-adjusted content bounds. Feature routes must not add
those insets again: duplicated route-specific clearance pushes feedback too
high and becomes stale when screen chrome changes. User-visible content comes
from the English and Arabic localization sources; mixed Trash batches reuse the
localized item-count and Trash labels. Verify narrow width, landscape,
right-to-left layout, and 200% text scaling whenever the feedback layout
changes.

When feedback originates inside a `PopupRoute` such as a modal bottom sheet,
the coordinator uses the root overlay instead of the page Scaffold messenger.
That keeps the same feedback bar, queue, timeout, action, and dismissal
semantics while placing it above the modal barrier and sheet. The overlay uses
the same directional 16-dp sides and 12-dp visual bottom gap, plus the larger of
the keyboard or bottom safe-area obstruction.

## Validation

Focused coordinator coverage is in `test/feedback_coordinator_test.dart`,
including the 12-dp gap above real Scaffold bottom navigation and floating
actions, and interactive feedback above a modal-sheet barrier.
Widget integration coverage is in `test/widget_test.dart`. Tests cover protected
Undo, compatible and incompatible batches, visible count, deadline reset,
LIFO/exactly-once execution, callback failure, accessible persistence, and the
four Trash restoration call sites.

Physical-device evidence is still required for TalkBack announcements,
hardware focus, keyboard and floating-action-button overlap, route transitions,
and rapid gestures during SnackBar animation.

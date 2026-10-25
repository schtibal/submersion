import 'package:flutter/material.dart';

import 'package:submersion/l10n/l10n_extension.dart';

/// The shape a detail card takes while it is in edit mode: the usual card
/// corners, outlined in the primary colour so the open card stands out.
ShapeBorder inlineEditCardShape(BuildContext context) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
);

/// A detail card's header actions (issue #2976): [actions] in view mode;
/// in edit mode [editingActions], then Cancel and Save as the embedded edit
/// forms show them.
class InlineEditActions extends StatelessWidget {
  const InlineEditActions({
    super.key,
    required this.editing,
    required this.saving,
    required this.onCancel,
    required this.onSave,
    this.actions = const [],
    this.editingActions = const [],
  });

  final bool editing;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final List<Widget> actions;
  final List<Widget> editingActions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!editing) {
      return Row(mainAxisSize: MainAxisSize.min, children: actions);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...editingActions,
        TextButton(
          onPressed: saving ? null : onCancel,
          child: Text(l10n.forms_cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: saving ? null : onSave,
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.forms_save),
        ),
      ],
    );
  }
}

/// The header of a plain detail card: its title and, at the right,
/// [actions].
class InlineEditCardHeader extends StatelessWidget {
  const InlineEditCardHeader({
    super.key,
    required this.title,
    required this.actions,
  });

  final String title;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: actions),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reports a failed save without leaving edit mode.
void showInlineSaveFailed(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.diveLog_detail_inlineSaveFailed('$error')),
    ),
  );
}

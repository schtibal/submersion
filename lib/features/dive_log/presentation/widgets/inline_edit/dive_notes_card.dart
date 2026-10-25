import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/inline_edit_header.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/inline_edit_session.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// The dive detail page's Notes card, editable in place (issue #2976).
class DiveNotesCard extends ConsumerStatefulWidget {
  const DiveNotesCard({super.key, required this.dive});

  final Dive dive;

  @override
  ConsumerState<DiveNotesCard> createState() => _DiveNotesCardState();
}

class _DiveNotesCardState extends ConsumerState<DiveNotesCard> {
  /// The editor's height before the diver drags it taller, in lines.
  static const _minLines = 8;

  /// Roughly one line of the field's text, the step a drag adds.
  static const _lineHeight = 24.0;

  TextEditingController? _controller;
  bool _saving = false;

  /// Lines the diver added by dragging the grip.
  int _extraLines = 0;
  double _dragAccumulated = 0;

  /// The text just saved, shown until the refreshed dive arrives so the card
  /// does not flash the old notes in between.
  String? _savedNotes;

  bool get _editing => _controller != null;

  String get _notes => _savedNotes ?? widget.dive.notes;

  InlineEditNotifier get _session =>
      ref.read(inlineEditNotifierProvider(widget.dive.id).notifier);

  @override
  void didUpdateWidget(DiveNotesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dive.notes != oldWidget.dive.notes) _savedNotes = null;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _begin() {
    if (!_session.begin(InlineEditCard.notes)) return;
    final controller = TextEditingController(text: _notes);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.addListener(() {
      _session.setDirty(InlineEditCard.notes, controller.text != _notes);
    });
    setState(() {
      _controller = controller;
      _extraLines = 0;
      _dragAccumulated = 0;
    });
  }

  void _close() {
    final controller = _controller;
    setState(() => _controller = null);
    controller?.dispose();
    _session.end(InlineEditCard.notes);
  }

  Future<void> _save() async {
    final text = _controller!.text;
    setState(() => _saving = true);
    try {
      await ref.read(diveRepositoryProvider).setNotes(widget.dive.id, text);
      if (!mounted) return;
      ref.invalidate(diveProvider(widget.dive.id));
      _savedNotes = text;
      _close();
    } catch (e) {
      if (mounted) showInlineSaveFailed(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final session = ref.watch(inlineEditNotifierProvider(widget.dive.id));
    final otherCardOpen =
        session != null && session.card != InlineEditCard.notes;

    return Card(
      shape: _editing ? inlineEditCardShape(context) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InlineEditCardHeader(
              title: l10n.diveLog_detail_section_notes,
              actions: InlineEditActions(
                editing: _editing,
                saving: _saving,
                onCancel: _close,
                onSave: _save,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: l10n.diveLog_detail_editNotes,
                    color: theme.colorScheme.primary,
                    onPressed: otherCardOpen ? null : _begin,
                  ),
                ],
              ),
            ),
            const Divider(),
            if (_editing)
              _editor(context)
            else if (_notes.isNotEmpty)
              SelectableText(_notes, style: theme.textTheme.bodyMedium)
            else
              Text(
                l10n.diveLog_detail_noNotes,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _editor(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            // Grows with its text; the grip adds rows beyond what the text
            // needs.
            minLines: _minLines + _extraLines,
            maxLines: null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.diveLog_detail_section_notes,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Semantics(
            container: true,
            label: l10n.diveLog_detail_resizeNotes,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  _dragAccumulated += details.delta.dy;
                  final lines = (_dragAccumulated / _lineHeight).round();
                  final next = lines < 0 ? 0 : lines;
                  if (next != _extraLines) setState(() => _extraLines = next);
                },
                onVerticalDragEnd: (_) =>
                    _dragAccumulated = _extraLines * _lineHeight,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CustomPaint(
                    painter: _GripPainter(
                      Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two short diagonal strokes in the corner, the usual resize grip.
class _GripPainter extends CustomPainter {
  const _GripPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final right = size.width - 8;
    final bottom = size.height - 8;
    canvas.drawLine(
      Offset(right, bottom - 10),
      Offset(right - 10, bottom),
      paint,
    );
    canvas.drawLine(
      Offset(right, bottom - 5),
      Offset(right - 5, bottom),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GripPainter oldDelegate) => oldDelegate.color != color;
}

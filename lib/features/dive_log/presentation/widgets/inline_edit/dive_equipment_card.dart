import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_detail_ui_providers.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/utils/dive_service_status.dart';
import 'package:submersion/features/dive_log/presentation/widgets/collapsible_section.dart';
import 'package:submersion/features/dive_log/presentation/widgets/dive_gear_tree_view.dart';
import 'package:submersion/features/dive_log/presentation/widgets/dive_gear_with_figure.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/inline_edit_header.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/inline_edit_session.dart';
import 'package:submersion/features/dive_log/presentation/widgets/pickers/equipment_picker_sheet.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/features/equipment/domain/entities/equipment_item.dart';
import 'package:submersion/features/equipment/domain/entities/gear_link.dart';
import 'package:submersion/features/equipment/domain/entities/gear_provenance.dart';
import 'package:submersion/features/equipment/domain/services/gear_expander.dart';
import 'package:submersion/features/equipment/domain/services/gear_tree.dart';
import 'package:submersion/features/equipment/presentation/helpers/gear_expansion.dart';
import 'package:submersion/features/equipment/presentation/widgets/equipment_arrange_sheet.dart';
import 'package:submersion/features/equipment/presentation/widgets/observation_status_chip.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// The dive detail page's Equipment card, editable in place (issue #2976).
///
/// Add picks gear through the same sheet as the dive editor; from view mode
/// its confirmation saves straight away. Edit opens a draft in which any row,
/// part or set can be removed; Save writes it.
class DiveEquipmentCard extends ConsumerStatefulWidget {
  const DiveEquipmentCard({super.key, required this.dive});

  final Dive dive;

  @override
  ConsumerState<DiveEquipmentCard> createState() => _DiveEquipmentCardState();
}

/// A gear list held as the dive editor holds it: the items in their own
/// order, and one provenance row per item.
typedef _Gear = ({List<EquipmentItem> items, List<GearProvenance> rows});

class _DiveEquipmentCardState extends ConsumerState<DiveEquipmentCard> {
  /// The draft; null outside edit mode.
  _Gear? _draft;
  bool _saving = false;

  bool get _editing => _draft != null;

  String get _diveId => widget.dive.id;

  InlineEditNotifier get _session =>
      ref.read(inlineEditNotifierProvider(_diveId).notifier);

  _Gear get _saved =>
      (items: widget.dive.equipment, rows: widget.dive.gearProvenance);

  static bool _sameRows(List<GearProvenance> a, List<GearProvenance> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _expand() =>
      ref.read(collapsibleSectionProvider.notifier).setEquipmentExpanded(true);

  void _begin() {
    if (!_session.begin(InlineEditCard.equipment)) return;
    _expand();
    setState(() => _draft = _saved);
  }

  void _setDraft(_Gear gear) {
    setState(() => _draft = gear);
    _session.setDirty(
      InlineEditCard.equipment,
      !_sameRows(gear.rows, _saved.rows),
    );
  }

  /// Applies a removal: [rows] is the gear that stays, with provenance.
  void _keepRows(List<GearProvenance> rows) {
    final keep = {for (final p in rows) p.equipmentId};
    _setDraft((
      items: [
        for (final e in _draft!.items)
          if (keep.contains(e.id)) e,
      ],
      rows: rows,
    ));
  }

  void _close() {
    setState(() => _draft = null);
    _session.end(InlineEditCard.equipment);
  }

  Future<void> _write(List<GearProvenance> rows) async {
    await ref.read(diveRepositoryProvider).setDiveGear(_diveId, rows);
    ref.invalidate(diveProvider(_diveId));
  }

  Future<void> _save() async {
    final rows = _draft!.rows;
    setState(() => _saving = true);
    try {
      if (!_sameRows(rows, _saved.rows)) await _write(rows);
      if (mounted) _close();
    } catch (e) {
      if (mounted) showInlineSaveFailed(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// [picked] added to [gear], each assembly bringing its parts the way the
  /// dive editor attaches them.
  Future<_Gear> _withAdded(_Gear gear, List<EquipmentItem> picked) async {
    final merged = [
      ...gear.items,
      for (final item in picked)
        if (!gear.items.any((e) => e.id == item.id)) item,
    ];
    String? diverId = widget.dive.diverId;
    if (diverId == null) {
      try {
        diverId = await ref.read(validatedCurrentDiverIdProvider.future);
      } catch (_) {
        diverId = null;
      }
    }
    final expansion = await expandGearOnPage(
      ref,
      additions: [for (final i in picked) (equipmentId: i.id, viaSetId: null)],
      existing: gear.rows,
      existingItems: merged,
      diverId: diverId,
    );
    return (
      items: [...merged, ...expansion.newItems],
      rows: expansion.provenance,
    );
  }

  Future<void> _add() async {
    final picked = await _pickEquipment(
      (_draft ?? _saved).items.map((e) => e.id).toSet(),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    _expand();
    try {
      if (_editing) {
        final next = await _withAdded(_draft!, picked);
        if (mounted && _editing) _setDraft(next);
        return;
      }
      // Confirming in the picker is the confirmation, so a view-mode add
      // saves.
      final next = await _withAdded(_saved, picked);
      await _write(next.rows);
    } catch (e) {
      if (mounted) showInlineSaveFailed(context, e);
    }
  }

  Future<List<EquipmentItem>?> _pickEquipment(Set<String> selectedIds) {
    return showModalBottomSheet<List<EquipmentItem>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => EquipmentPickerSheet(
          scrollController: scrollController,
          selectedEquipmentIds: selectedIds,
          hideSpare: true,
          // A dive logged after the fact may have used gear since retired
          // or sold (#3210).
          offerLeftKit: true,
          // Multi-select, so a full kit goes on in one pass (#2175).
          onEquipmentConfirmed: (items) => Navigator.of(context).pop(items),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final session = ref.watch(inlineEditNotifierProvider(_diveId));
    final otherCardOpen =
        session != null && session.card != InlineEditCard.equipment;
    final isExpanded = ref.watch(equipmentSectionExpandedProvider);
    final addButton = IconButton(
      icon: const Icon(Icons.add),
      tooltip: l10n.diveLog_detail_addEquipment,
      color: theme.colorScheme.primary,
      onPressed: otherCardOpen || _saving ? null : _add,
    );

    // Collapsed subtitle showing the top-level row count as the tree view
    // places it: an assembly's parts sit inside its row, and an orphaned
    // row is promoted, so the count matches what expands below (#1487).
    final collapsedSubtitle = l10n.diveLog_detail_equipmentCount(
      GearTree.topLevelCount(widget.dive.gearProvenance),
    );

    return CollapsibleCardSection(
      title: l10n.diveLog_detail_section_equipment,
      icon: Icons.backpack,
      collapsedSubtitle: collapsedSubtitle,
      isExpanded: isExpanded,
      collapsible: !_editing,
      shape: _editing ? inlineEditCardShape(context) : null,
      // The header is one large InkWell that toggles the card, so these
      // buttons consume their own taps: without that, acting on the gear
      // would also collapse the section the diver was looking at.
      trailing: FittedBox(
        fit: BoxFit.scaleDown,
        child: InlineEditActions(
          editing: _editing,
          saving: _saving,
          onCancel: _close,
          onSave: _save,
          editingActions: [addButton],
          actions: [
            IconButton(
              icon: const Icon(Icons.sort, size: 20),
              tooltip: l10n.equipment_list_sortTooltip,
              onPressed: () => showEquipmentArrangeSheet(context),
            ),
            addButton,
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              tooltip: l10n.diveLog_detail_editEquipment,
              color: theme.colorScheme.primary,
              onPressed: otherCardOpen ? null : _begin,
            ),
          ],
        ),
      ),
      onToggle: (expanded) {
        ref
            .read(collapsibleSectionProvider.notifier)
            .setEquipmentExpanded(expanded);
      },
      contentBuilder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _editing ? _editContent(context) : _viewContent(context),
      ),
    );
  }

  Widget _viewContent(BuildContext context) {
    final dive = widget.dive;
    if (dive.equipment.isEmpty) {
      return _emptyText(context, context.l10n.diveLog_detail_noEquipment);
    }
    // The tree, and the diver figure above it when the diver has turned it
    // on (issue #2326). It marks gear another profile owns against this
    // dive's diver, as the tree alone did (issue #2046).
    return DiveGearWithFigure(
      dive: dive,
      showFigure: ref.watch(settingsProvider.select((s) => s.showDiveFigure)),
      showServiceStatus: diveGearShowsLiveServiceStatus(dive, DateTime.now()),
      onTap: (item) => context.push('/equipment/${item.id}'),
      // The check-in chip for each row (condition phase 3a).
      rowTrailing: (item) => ObservationStatusChip(equipment: item, dive: dive),
    );
  }

  Widget _editContent(BuildContext context) {
    final draft = _draft!;
    if (draft.items.isEmpty) {
      return _emptyText(context, context.l10n.diveLog_edit_noEquipmentSelected);
    }
    // Removals are by id, never by display index: a render position
    // addresses a different item under an arrangement.
    return DiveGearTreeView(
      links: gearLinksFor(draft.items, draft.rows),
      ownerReferenceDiverId: widget.dive.diverId,
      showServiceStatus: diveGearShowsLiveServiceStatus(
        widget.dive,
        DateTime.now(),
      ),
      onRemoveSet: (setId) =>
          _keepRows(GearExpander.removeSet(draft.rows, setId)),
      onRemoveSubtree: (id) =>
          _keepRows(GearExpander.removeSubtree(draft.rows, id)),
      onRemovePart: (id) => _keepRows(GearExpander.removePart(draft.rows, id)),
    );
  }

  Widget _emptyText(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

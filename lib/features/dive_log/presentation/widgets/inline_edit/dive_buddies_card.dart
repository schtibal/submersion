import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/buddies/domain/entities/buddy.dart';
import 'package:submersion/features/buddies/presentation/providers/buddy_providers.dart';
import 'package:submersion/features/buddies/presentation/widgets/buddy_picker.dart';
import 'package:submersion/features/buddies/presentation/widgets/buddy_role_pickers.dart';
import 'package:submersion/features/buddies/presentation/widgets/legacy_buddy_text_section.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/inline_edit_header.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/inline_edit_session.dart';
import 'package:submersion/features/dive_log/presentation/widgets/logged_with_tiles.dart';
import 'package:submersion/features/dive_roles/domain/entities/dive_role.dart';
import 'package:submersion/features/dive_roles/presentation/dive_role_list_display.dart';
import 'package:submersion/features/dive_roles/presentation/providers/dive_role_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/shared/widgets/profile_photo/profile_avatar.dart';

/// The dive detail page's Buddies card, editable in place (issue #2976).
///
/// Add picks buddies through the same sheet as the dive editor; from view
/// mode its Done saves straight away. Edit opens a draft in which each row
/// can change its roles and each buddy can be removed; Save writes it.
class DiveBuddiesCard extends ConsumerStatefulWidget {
  const DiveBuddiesCard({super.key, required this.dive});

  final Dive dive;

  @override
  ConsumerState<DiveBuddiesCard> createState() => _DiveBuddiesCardState();
}

class _DiveBuddiesCardState extends ConsumerState<DiveBuddiesCard> {
  /// The draft buddy list; null outside edit mode.
  List<BuddyWithRole>? _draftBuddies;
  List<String> _draftRoleIds = const [];

  /// What the draft started from, to tell whether it changed.
  List<BuddyWithRole> _originalBuddies = const [];
  List<String> _originalRoleIds = const [];

  /// Roles offered even when hidden from the pickers (issue #401): the ones
  /// the dive had when editing began, as the dive editor keeps them.
  Set<String> _keepRoleIds = const {};

  bool _saving = false;

  /// The diver's roles just saved, shown until the refreshed dive arrives.
  List<String>? _savedRoleIds;

  /// The buddies just saved, shown until the reloaded list arrives: while
  /// it reloads the provider still holds the old list, which would flash
  /// back for a few frames.
  List<BuddyWithRole>? _savedBuddies;

  bool get _editing => _draftBuddies != null;

  List<String> get _diverRoleIds => _savedRoleIds ?? widget.dive.diverRoleIds;

  String get _diveId => widget.dive.id;

  InlineEditNotifier get _session =>
      ref.read(inlineEditNotifierProvider(_diveId).notifier);

  @override
  void didUpdateWidget(DiveBuddiesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.dive.diverRoleIds, oldWidget.dive.diverRoleIds)) {
      _savedRoleIds = null;
    }
  }

  static bool _sameBuddies(List<BuddyWithRole> a, List<BuddyWithRole> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].buddy.id != b[i].buddy.id ||
          !listEquals(a[i].roleIds, b[i].roleIds)) {
        return false;
      }
    }
    return true;
  }

  void _begin(List<BuddyWithRole> linked) {
    if (!_session.begin(InlineEditCard.buddies)) return;
    final roleIds = _diverRoleIds;
    setState(() {
      _originalBuddies = linked;
      _originalRoleIds = roleIds;
      _draftBuddies = List.of(linked);
      _draftRoleIds = List.of(roleIds);
      _keepRoleIds = {...roleIds, for (final b in linked) ...b.roleIds};
    });
  }

  void _updateDraft({List<BuddyWithRole>? buddies, List<String>? roleIds}) {
    setState(() {
      if (buddies != null) _draftBuddies = buddies;
      if (roleIds != null) _draftRoleIds = roleIds;
    });
    _session.setDirty(
      InlineEditCard.buddies,
      !_sameBuddies(_draftBuddies!, _originalBuddies) ||
          !listEquals(_draftRoleIds, _originalRoleIds),
    );
  }

  void _close() {
    setState(() => _draftBuddies = null);
    _session.end(InlineEditCard.buddies);
  }

  Future<void> _writeBuddies(
    List<BuddyWithRole> before,
    List<BuddyWithRole> after,
  ) async {
    await ref.read(buddyRepositoryProvider).setBuddiesForDive(_diveId, after);
    if (mounted) setState(() => _savedBuddies = after);
    invalidateDiveBuddyLinks(ref, _diveId, {
      for (final b in before) b.buddy.id,
      for (final b in after) b.buddy.id,
    });
  }

  Future<void> _save() async {
    final buddies = _draftBuddies!;
    final roleIds = _draftRoleIds;
    setState(() => _saving = true);
    try {
      if (!_sameBuddies(buddies, _originalBuddies)) {
        await _writeBuddies(_originalBuddies, buddies);
      }
      if (!listEquals(roleIds, _originalRoleIds)) {
        await ref.read(diveRepositoryProvider).setDiverRoles(_diveId, roleIds);
        ref.invalidate(diveProvider(_diveId));
        _savedRoleIds = roleIds;
      }
      if (mounted) _close();
    } catch (e) {
      if (mounted) showInlineSaveFailed(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add(List<BuddyWithRole> linked) async {
    final current = _draftBuddies ?? linked;
    final picked = await showBuddySelectionSheet(context, current);
    if (picked == null || !mounted) return;
    if (_editing) {
      _updateDraft(buddies: picked);
      return;
    }
    if (_sameBuddies(picked, linked)) return;
    // Done in the sheet is the confirmation, so a view-mode add saves.
    try {
      await _writeBuddies(linked, picked);
    } catch (e) {
      if (mounted) showInlineSaveFailed(context, e);
    }
  }

  Future<void> _changeBuddyRoles(BuddyWithRole bwr) async {
    final picked = await pickBuddyRoles(
      context,
      ref,
      buddyWithRole: bwr,
      keepRoleIds: _keepRoleIds,
    );
    if (picked == null || !mounted || !_editing) return;
    _updateDraft(
      buddies: [
        for (final b in _draftBuddies!)
          b.buddy.id == bwr.buddy.id
              ? BuddyWithRole(buddy: b.buddy, roles: picked)
              : b,
      ],
    );
  }

  Future<void> _changeMyRoles() async {
    final picked = await pickDiverRoles(
      context,
      ref,
      diverRoleIds: _draftRoleIds,
      keepRoleIds: _keepRoleIds,
    );
    if (picked == null || !mounted || !_editing) return;
    _updateDraft(roleIds: picked);
  }

  void _remove(BuddyWithRole bwr) {
    _updateDraft(
      buddies: [
        for (final b in _draftBuddies!)
          if (b.buddy.id != bwr.buddy.id) b,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Kept loaded for the role selectors, which read it.
    ref.watch(allDiveRolesProvider);
    // The reloaded list has arrived once the provider settles on data.
    ref.listen(buddiesForDiveProvider(_diveId), (previous, next) {
      if (_savedBuddies != null && next.hasValue && !next.isLoading) {
        setState(() => _savedBuddies = null);
      }
    });
    final buddiesAsync = ref.watch(buddiesForDiveProvider(_diveId));
    final linked = _savedBuddies ?? buddiesAsync.valueOrNull;
    if (linked == null && !_editing) {
      if (buddiesAsync.hasError) return const SizedBox.shrink();
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return _card(context, linked ?? _originalBuddies);
  }

  Widget _card(BuildContext context, List<BuddyWithRole> linked) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final session = ref.watch(inlineEditNotifierProvider(_diveId));
    final otherCardOpen =
        session != null && session.card != InlineEditCard.buddies;
    final addButton = IconButton(
      icon: const Icon(Icons.add),
      tooltip: l10n.diveLog_detail_addBuddy,
      color: theme.colorScheme.primary,
      onPressed: otherCardOpen || _saving ? null : () => _add(linked),
    );

    return Card(
      shape: _editing ? inlineEditCardShape(context) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InlineEditCardHeader(
              title: l10n.diveLog_detail_section_buddies,
              actions: InlineEditActions(
                editing: _editing,
                saving: _saving,
                onCancel: _close,
                onSave: _save,
                editingActions: [addButton],
                actions: [
                  if (linked.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        l10n.diveLog_detail_buddyCount(linked.length),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  addButton,
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: l10n.diveLog_detail_editBuddies,
                    color: theme.colorScheme.primary,
                    onPressed: otherCardOpen ? null : () => _begin(linked),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (_editing)
              ..._editRows(context)
            else
              ..._viewRows(context, linked),
          ],
        ),
      ),
    );
  }

  List<Widget> _viewRows(BuildContext context, List<BuddyWithRole> linked) {
    final theme = Theme.of(context);
    // The dive_buddies junction is authoritative once it holds anyone. The
    // legacy free-text dives.buddy and dives.dive_master columns are only a
    // fallback for a dive whose people were never linked, such as a CSV
    // import, so such a dive is not called solo, and the section offers to
    // link the text to buddy records (#1831). A text holding only a
    // placeholder like "None" does not count.
    final showLegacyText =
        linked.isEmpty && LegacyBuddyTextSection.hasContent(widget.dive);
    return [
      if (_diverRoleIds.isNotEmpty) _myRoleTile(context),
      if (showLegacyText)
        LegacyBuddyTextSection(dive: widget.dive)
      else if (linked.isEmpty && _diverRoleIds.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            context.l10n.diveLog_detail_soloDive,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        )
      else
        ...linked.map((bwr) => _buddyTile(context, bwr)),
      // Other profiles' logs of this outing (issue #2002).
      LoggedWithTiles(diveId: _diveId),
    ];
  }

  List<Widget> _editRows(BuildContext context) {
    final l10n = context.l10n;
    final rolesById =
        ref.watch(diveRoleMapProvider).value ?? const <String, DiveRole>{};
    return [
      _editRow(
        context,
        leading: _meAvatar(context),
        title: l10n.buddies_picker_me,
        subtitle: _draftRoleIds.isEmpty
            ? l10n.buddies_picker_setMyRole
            : rolesForIds(_draftRoleIds, rolesById).joinedLocalizedNames(l10n),
        onChangeRole: _changeMyRoles,
      ),
      for (final bwr in _draftBuddies!)
        _editRow(
          context,
          leading: _buddyAvatar(context, bwr.buddy),
          title: bwr.buddy.name,
          subtitle: bwr.roles.joinedLocalizedNames(l10n),
          onChangeRole: () => _changeBuddyRoles(bwr),
          onRemove: () => _remove(bwr),
        ),
    ];
  }

  Widget _editRow(
    BuildContext context, {
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onChangeRole,
    VoidCallback? onRemove,
  }) {
    final l10n = context.l10n;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: l10n.diveLog_detail_changeRole,
            onPressed: _saving ? null : onChangeRole,
          ),
          // Me has no X; the empty slot keeps the pencils in one column.
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: l10n.diveLog_detail_removeBuddy,
              onPressed: _saving ? null : onRemove,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buddyAvatar(BuildContext context, Buddy buddy) => ProfileAvatar(
    photo: buddy.photo,
    initials: buddy.initials,
    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
  );

  Widget _meAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: colorScheme.primaryContainer,
      child: Icon(Icons.person, color: colorScheme.onPrimaryContainer),
    );
  }

  Widget _buddyTile(BuildContext context, BuddyWithRole bwr) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _buddyAvatar(context, bwr.buddy),
      title: Text(bwr.buddy.name),
      subtitle: Text(bwr.roles.joinedLocalizedNames(context.l10n)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => context.push('/buddies/${bwr.buddy.id}'),
    );
  }

  /// The active diver's own roles on this dive (#547, #1221), shown above
  /// buddies.
  Widget _myRoleTile(BuildContext context) {
    final rolesById =
        ref.watch(diveRoleMapProvider).value ?? const <String, DiveRole>{};
    final label = rolesForIds(
      _diverRoleIds,
      rolesById,
    ).joinedLocalizedNames(context.l10n);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _meAvatar(context),
      title: Text(context.l10n.buddies_picker_me),
      subtitle: Text(label),
    );
  }
}

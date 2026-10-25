import 'package:flutter/material.dart';

import 'package:submersion/core/built_ins/built_in_catalog.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/buddies/domain/entities/buddy.dart';
import 'package:submersion/features/dive_roles/domain/entities/dive_role.dart';
import 'package:submersion/features/dive_roles/presentation/providers/dive_role_providers.dart';
import 'package:submersion/features/dive_roles/presentation/widgets/dive_role_selector_sheet.dart';
import 'package:submersion/features/settings/presentation/providers/hidden_built_ins_provider.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Creates a custom dive role named [name] from a role selector, reporting a
/// failure in a snackbar. Null when it could not be created.
Future<DiveRole?> createCustomDiveRole(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  try {
    return await ref
        .read(diveRoleListNotifierProvider.notifier)
        .addDiveRoleByName(name);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.diveRoles_snackbar_errorAdding(e))),
      );
    }
    return null;
  }
}

/// Opens the role selector for a buddy on a dive. Null when dismissed; a
/// buddy left with no role is a plain Buddy.
///
/// The caller keeps [allDiveRolesProvider] watched, so the roles are loaded.
Future<List<DiveRole>?> pickBuddyRoles(
  BuildContext context,
  WidgetRef ref, {
  required BuddyWithRole buddyWithRole,
  Set<String> keepRoleIds = const {},
}) async {
  final selection = await showDiveRoleSelector(
    context,
    title: context.l10n.buddies_picker_selectRole(buddyWithRole.buddy.name),
    roles: ref.read(allDiveRolesProvider).value ?? const <DiveRole>[],
    selectedRoleIds: buddyWithRole.roleIds,
    hiddenRoleIds: ref.read(hiddenBuiltInIdsProvider(BuiltInCatalog.diveRoles)),
    keepRoleIds: keepRoleIds,
    onCreateCustomRole: (name) => createCustomDiveRole(context, ref, name),
  );
  if (selection == null) return null;
  return selection.isEmpty ? [DiveRole.builtInBuddy()] : selection;
}

/// Opens the role selector for the active diver's own roles on a dive. Null
/// when dismissed; an empty list clears them.
Future<List<String>?> pickDiverRoles(
  BuildContext context,
  WidgetRef ref, {
  required List<String> diverRoleIds,
  Set<String> keepRoleIds = const {},
}) async {
  final selection = await showDiveRoleSelector(
    context,
    title: context.l10n.buddies_picker_selectMyRole,
    roles: ref.read(allDiveRolesProvider).value ?? const <DiveRole>[],
    hiddenRoleIds: ref.read(hiddenBuiltInIdsProvider(BuiltInCatalog.diveRoles)),
    keepRoleIds: keepRoleIds,
    allowEmpty: true,
    selectedRoleIds: diverRoleIds,
  );
  if (selection == null) return null;
  return [for (final r in selection) r.id];
}

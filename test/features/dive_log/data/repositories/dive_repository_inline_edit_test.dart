import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    as domain;
import 'package:submersion/features/dive_roles/domain/entities/dive_role.dart';
import 'package:submersion/features/dive_roles/domain/services/dive_role_set.dart';
import 'package:submersion/features/equipment/domain/entities/equipment_item.dart';
import 'package:submersion/features/equipment/domain/entities/gear_link.dart';
import 'package:submersion/features/equipment/domain/entities/gear_provenance.dart';

import '../../../../helpers/test_database.dart';

/// The single-purpose writes behind the dive detail cards' edit modes
/// (issue #2976): each touches only its own data, so a card cannot overwrite
/// a field another device changed while the card was open.
void main() {
  late AppDatabase db;
  late DiveRepository repo;

  Future<void> seedEquipment(String id) => db
      .into(db.equipment)
      .insert(
        EquipmentCompanion.insert(
          id: id,
          name: id,
          type: 'regulator',
          createdAt: 1,
          updatedAt: 1,
        ),
      );

  EquipmentItem item(String id) =>
      EquipmentItem(id: id, name: id, type: EquipmentType.regulator);

  Future<Dive> rowOf(String id) =>
      (db.select(db.dives)..where((t) => t.id.equals(id))).getSingle();

  Future<Set<String>> pending(String entityType) async => {
    for (final r in await db.select(db.syncRecords).get())
      if (r.entityType == entityType) r.recordId,
  };

  setUp(() async {
    db = await setUpTestDatabase();
    repo = DiveRepository();
    for (final id in ['fins', 'mask', 'reg']) {
      await seedEquipment(id);
    }
    await repo.createDive(
      domain.Dive(
        id: 'dv',
        name: 'North wall',
        notes: 'Old notes',
        dateTime: DateTime(2026, 1, 1),
        gear: looseGear([item('fins'), item('mask')]),
      ),
    );
    await db.delete(db.syncRecords).go();
  });

  tearDown(tearDownTestDatabase);

  group('setNotes', () {
    test('writes the notes and nothing else', () async {
      final before = await rowOf('dv');

      await repo.setNotes('dv', 'Eagle rays at 18 m\n');

      final after = await rowOf('dv');
      expect(after.notes, 'Eagle rays at 18 m\n');
      expect(after.name, 'North wall');
      expect(after.updatedAt, greaterThanOrEqualTo(before.updatedAt));
      expect(await pending('dives'), {'dv'});
    });
  });

  group('setDiverRoles', () {
    test('writes the primary role and the full set', () async {
      await repo.setDiverRoles('dv', [
        DiveRole.instructorId,
        DiveRole.diveGuideId,
      ]);

      final dive = await repo.getDiveById('dv');
      // The set reads back in its canonical order, not the order given.
      expect(
        dive!.diverRoleIds,
        unorderedEquals([DiveRole.instructorId, DiveRole.diveGuideId]),
      );
      expect(
        (await rowOf('dv')).diverRole,
        DiveRoleSet.primary([DiveRole.instructorId, DiveRole.diveGuideId]),
      );
      expect((await rowOf('dv')).notes, 'Old notes');
      expect(await pending('dives'), contains('dv'));
    });

    test('an empty list clears the roles', () async {
      await repo.setDiverRoles('dv', [DiveRole.instructorId]);
      await repo.setDiverRoles('dv', const []);

      final dive = await repo.getDiveById('dv');
      expect(dive!.diverRoleIds, isEmpty);
    });
  });

  group('setDiveGear', () {
    test('makes the gear rows equal to the links, with provenance', () async {
      await repo.setDiveGear('dv', const [
        GearProvenance(equipmentId: 'fins'),
        GearProvenance(equipmentId: 'reg', viaSetId: null),
      ]);

      final rows = await (db.select(
        db.diveEquipment,
      )..where((t) => t.diveId.equals('dv'))).get();
      expect(rows.map((r) => r.equipmentId), unorderedEquals(['fins', 'reg']));
      // Only the added row is re-marked; the unchanged one is left alone.
      expect(await pending('diveEquipment'), {'dv|reg'});
      expect(await pending('dives'), {'dv'});
      expect((await rowOf('dv')).notes, 'Old notes');
    });
  });

  test('the dive row keeps fields the card does not own', () async {
    await (db.update(db.dives)..where((t) => t.id.equals('dv'))).write(
      const DivesCompanion(rating: Value(4)),
    );

    await repo.setNotes('dv', 'New');
    await repo.setDiverRoles('dv', [DiveRole.instructorId]);
    await repo.setDiveGear('dv', const [GearProvenance(equipmentId: 'mask')]);

    expect((await rowOf('dv')).rating, 4);
  });
}

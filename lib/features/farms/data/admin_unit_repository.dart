import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_database.dart';
import '../models/admin_unit.dart';

/// Read-only access to the location tree downloaded during sync.
class AdminUnitRepository {
  AdminUnitRepository(this.db);

  final Database db;

  /// Counties; empty until the office has loaded locations and the device has synced.
  Future<List<AdminUnit>> topLevel() => _query('parent_id IS NULL', const []);

  /// Units under [parentId]. Under a county, [level] picks one branch:
  /// SUB_COUNTY (county government) or LOCATION (national government).
  Future<List<AdminUnit>> children(int parentId, {String? level}) => level == null
      ? _query('parent_id = ?', [parentId])
      : _query('parent_id = ? AND level = ?', [parentId, level]);

  Future<bool> hasChildren(int unitId) async {
    final rows = await db.query(Tables.adminUnits,
        columns: ['unit_id'], where: 'parent_id = ?', whereArgs: [unitId], limit: 1);
    return rows.isNotEmpty;
  }

  /// The unit and every unit above it, county first.
  Future<List<AdminUnit>> path(int unitId) async {
    final rows = await db.rawQuery('''
      WITH RECURSIVE chain(unit_id, parent_id, level, name, depth) AS (
        SELECT unit_id, parent_id, level, name, 0 FROM ${Tables.adminUnits} WHERE unit_id = ?
        UNION ALL
        SELECT a.unit_id, a.parent_id, a.level, a.name, c.depth + 1
        FROM ${Tables.adminUnits} a JOIN chain c ON a.unit_id = c.parent_id
        WHERE c.depth < 10
      )
      SELECT * FROM chain ORDER BY depth DESC
    ''', [unitId]);
    return rows.map(AdminUnit.fromRow).toList();
  }

  Future<List<AdminUnit>> _query(String where, List<Object?> args) async {
    final rows = await db.query(Tables.adminUnits,
        where: where, whereArgs: args, orderBy: 'name COLLATE NOCASE');
    return rows.map(AdminUnit.fromRow).toList();
  }
}

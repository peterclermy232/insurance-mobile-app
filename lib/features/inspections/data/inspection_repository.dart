import 'dart:convert';

import '../../../core/db/app_database.dart';
import '../../../core/db/syncable.dart';
import '../models/inspection.dart';

class InspectionRepository extends SyncableRepository {
  InspectionRepository(super.db, super.changes);

  static const _select = '''
    SELECT i.*, fm.farm_name AS farm_name, (f.first_name || ' ' || f.last_name) AS farmer_name
    FROM ${Tables.inspections} i
    LEFT JOIN ${Tables.farms} fm ON fm.client_uuid = i.farm_uuid
    LEFT JOIN ${Tables.farmers} f ON f.client_uuid = fm.farmer_uuid
  ''';

  Future<List<Inspection>> list({String? farmUuid, String query = ''}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (farmUuid != null) {
      where.add('i.farm_uuid = ?');
      args.add(farmUuid);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add("(fm.farm_name LIKE ? OR (f.first_name || ' ' || f.last_name) LIKE ? OR i.inspection_type LIKE ?)");
      args.addAll(List.filled(3, '%$q%'));
    }
    final rows = await db.rawQuery(
        '$_select ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
        'ORDER BY i.scheduled_date DESC, i.updated_at DESC',
        args);
    return rows.map(Inspection.fromRow).toList();
  }

  Future<Inspection?> get(String uuid) async {
    final rows = await db.rawQuery('$_select WHERE i.client_uuid = ?', [uuid]);
    return rows.isEmpty ? null : Inspection.fromRow(rows.first);
  }

  Future<String> create(Inspection inspection) => insertNew(Tables.inspections, _columns(inspection));

  Future<void> update(String uuid, Inspection inspection) =>
      updateLocal(Tables.inspections, uuid, _columns(inspection));

  Map<String, Object?> _columns(Inspection i) {
    final values = i.toColumns();
    values['findings'] = jsonEncode(i.findings);
    return values;
  }

  Future<void> retryUpload(String uuid) => retry(Tables.inspections, uuid);
}

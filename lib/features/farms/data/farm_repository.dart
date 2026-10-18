import '../../../core/db/app_database.dart';
import '../../../core/db/syncable.dart';
import '../models/farm.dart';

class FarmRepository extends SyncableRepository {
  FarmRepository(super.db, super.changes);

  static const _select = '''
    SELECT fm.*, (f.first_name || ' ' || f.last_name) AS farmer_name, au.name AS unit_name,
      lu.name AS location_unit_name
    FROM ${Tables.farms} fm
    LEFT JOIN ${Tables.farmers} f ON f.client_uuid = fm.farmer_uuid
    LEFT JOIN ${Tables.adminUnits} au ON au.unit_id = fm.administrative_unit_id
    LEFT JOIN ${Tables.adminUnits} lu ON lu.unit_id = fm.location_unit_id
  ''';

  Future<List<Farm>> list({String query = '', String? farmerUuid}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (farmerUuid != null) {
      where.add('fm.farmer_uuid = ?');
      args.add(farmerUuid);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add("(fm.farm_name LIKE ? OR (f.first_name || ' ' || f.last_name) LIKE ? "
          'OR fm.location_province LIKE ? OR fm.location_district LIKE ? OR fm.location_sector LIKE ? '
          'OR fm.village LIKE ? OR fm.clan LIKE ? OR au.name LIKE ? OR lu.name LIKE ?)');
      args.addAll(List.filled(9, '%$q%'));
    }
    final rows = await db.rawQuery(
        '$_select ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY fm.farm_name', args);
    return rows.map(Farm.fromRow).toList();
  }

  Future<Farm?> get(String uuid) async {
    final rows = await db.rawQuery('$_select WHERE fm.client_uuid = ?', [uuid]);
    return rows.isEmpty ? null : Farm.fromRow(rows.first);
  }

  Future<String> create(Farm farm) => insertNew(Tables.farms, farm.toColumns());

  Future<void> update(String uuid, Farm farm) => updateLocal(Tables.farms, uuid, farm.toColumns());

  Future<void> retryUpload(String uuid) => retry(Tables.farms, uuid);
}

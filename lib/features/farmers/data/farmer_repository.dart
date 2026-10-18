import '../../../core/db/app_database.dart';
import '../../../core/db/syncable.dart';
import '../models/farmer.dart';

class FarmerRepository extends SyncableRepository {
  FarmerRepository(super.db, super.changes);

  static const _select = '''
    SELECT f.*, (SELECT COUNT(*) FROM ${Tables.farms} fm WHERE fm.farmer_uuid = f.client_uuid) AS farm_count,
      (SELECT m.file_path FROM ${Tables.media} m WHERE m.entity_uuid = f.client_uuid AND m.entity_type = 'farmer'
        ORDER BY m.id DESC LIMIT 1) AS local_photo
    FROM ${Tables.farmers} f
  ''';

  Future<List<Farmer>> list({String query = ''}) async {
    final q = query.trim();
    final rows = q.isEmpty
        ? await db.rawQuery('$_select ORDER BY f.updated_at DESC')
        : await db.rawQuery(
            "$_select WHERE (f.first_name || ' ' || f.last_name) LIKE ? OR f.id_number LIKE ? "
            'OR f.phone_number LIKE ? ORDER BY f.first_name, f.last_name',
            ['%$q%', '%$q%', '%$q%']);
    return rows.map(Farmer.fromRow).toList();
  }

  Future<Farmer?> get(String uuid) async {
    final rows = await db.rawQuery('$_select WHERE f.client_uuid = ?', [uuid]);
    return rows.isEmpty ? null : Farmer.fromRow(rows.first);
  }

  /// Another local farmer already using this national ID (catches double
  /// registration on the device before the server does).
  Future<Farmer?> findByIdNumber(String idNumber, {String? exceptUuid}) async {
    final rows = await db.rawQuery(
        '$_select WHERE f.id_number = ? AND f.client_uuid != ? LIMIT 1', [idNumber.trim(), exceptUuid ?? '']);
    return rows.isEmpty ? null : Farmer.fromRow(rows.first);
  }

  Future<String> create(Farmer farmer) => insertNew(Tables.farmers, farmer.toColumns());

  Future<void> update(String uuid, Farmer farmer) async {
    final values = farmer.toColumns();
    await updateLocal(Tables.farmers, uuid, {...values, 'notice': null});
  }

  Future<void> retryUpload(String uuid) => retry(Tables.farmers, uuid);
}

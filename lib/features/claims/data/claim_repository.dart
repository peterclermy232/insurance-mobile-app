import 'dart:convert';

import '../../../core/db/app_database.dart';
import '../../../core/db/syncable.dart';
import '../models/claim.dart';

class ClaimRepository extends SyncableRepository {
  ClaimRepository(super.db, super.changes);

  static const _select = '''
    SELECT c.*, q.policy_number AS policy_number, q.product_name AS product_name,
           q.sum_insured AS sum_insured, fm.farm_name AS farm_name, fm.farmer_uuid AS farmer_uuid,
           (f.first_name || ' ' || f.last_name) AS farmer_name
    FROM ${Tables.claims} c
    LEFT JOIN ${Tables.quotations} q ON q.client_uuid = c.quotation_uuid
    LEFT JOIN ${Tables.farms} fm ON fm.client_uuid = q.farm_uuid
    LEFT JOIN ${Tables.farmers} f ON f.client_uuid = fm.farmer_uuid
  ''';

  Future<List<Claim>> list({String? farmerUuid, String query = ''}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (farmerUuid != null) {
      where.add('fm.farmer_uuid = ?');
      args.add(farmerUuid);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add("(c.claim_number LIKE ? OR q.policy_number LIKE ? OR (f.first_name || ' ' || f.last_name) LIKE ?)");
      args.addAll(List.filled(3, '%$q%'));
    }
    final rows = await db.rawQuery(
        '$_select ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY c.updated_at DESC', args);
    return rows.map(Claim.fromRow).toList();
  }

  Future<Claim?> get(String uuid) async {
    final rows = await db.rawQuery('$_select WHERE c.client_uuid = ?', [uuid]);
    return rows.isEmpty ? null : Claim.fromRow(rows.first);
  }

  Future<String> create(Claim claim) => insertNew(Tables.claims, _columns(claim));

  Future<void> update(String uuid, Claim claim) => updateLocal(Tables.claims, uuid, _columns(claim));

  Map<String, Object?> _columns(Claim c) => {
        'quotation_uuid': c.quotationUuid,
        'estimated_loss_amount': c.estimatedLoss,
        'loss_details': jsonEncode(c.lossDetails()),
      };

  Future<void> retryUpload(String uuid) => retry(Tables.claims, uuid);
}

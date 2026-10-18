import 'dart:convert';

import '../../../core/db/app_database.dart';
import '../../../core/db/syncable.dart';
import '../models/quotation.dart';

class QuotationRepository extends SyncableRepository {
  QuotationRepository(super.db, super.changes);

  static const _select = '''
    SELECT q.*, fm.farm_name AS farm_name, fm.farmer_uuid AS farmer_uuid,
           (f.first_name || ' ' || f.last_name) AS farmer_name
    FROM ${Tables.quotations} q
    LEFT JOIN ${Tables.farms} fm ON fm.client_uuid = q.farm_uuid
    LEFT JOIN ${Tables.farmers} f ON f.client_uuid = fm.farmer_uuid
  ''';

  Future<List<Quotation>> list({String? farmUuid, String? farmerUuid, bool claimableOnly = false, String query = ''}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (farmUuid != null) {
      where.add('q.farm_uuid = ?');
      args.add(farmUuid);
    }
    if (farmerUuid != null) {
      where.add('fm.farmer_uuid = ?');
      args.add(farmerUuid);
    }
    if (claimableOnly) {
      where.add("q.server_id IS NOT NULL AND q.status IN ('WRITTEN', 'PAID')");
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add("(q.policy_number LIKE ? OR q.product_name LIKE ? OR fm.farm_name LIKE ? "
          "OR (f.first_name || ' ' || f.last_name) LIKE ?)");
      args.addAll(List.filled(4, '%$q%'));
    }
    final rows = await db.rawQuery(
        '$_select ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY q.updated_at DESC', args);
    return rows.map(Quotation.fromRow).toList();
  }

  Future<Quotation?> get(String uuid) async {
    final rows = await db.rawQuery('$_select WHERE q.client_uuid = ?', [uuid]);
    return rows.isEmpty ? null : Quotation.fromRow(rows.first);
  }

  /// ACTIVE products from the downloaded reference data.
  Future<List<InsuranceProduct>> activeProducts() async {
    final rows = await db.query(Tables.reference, where: 'kind = ?', whereArgs: ['insurance_products']);
    final products = rows
        .map((r) => InsuranceProduct.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>))
        .where((p) => p.isActive)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return products;
  }

  Future<String> create({required String farmUuid, required InsuranceProduct product, required double sumInsured}) =>
      insertNew(Tables.quotations, _columns(farmUuid, product, sumInsured));

  Future<void> update(String uuid,
          {required String farmUuid, required InsuranceProduct product, required double sumInsured}) =>
      updateLocal(Tables.quotations, uuid, _columns(farmUuid, product, sumInsured));

  Map<String, Object?> _columns(String farmUuid, InsuranceProduct product, double sumInsured) => {
        'farm_uuid': farmUuid,
        'insurance_product_id': product.id,
        'product_name': product.name,
        'sum_insured': sumInsured,
        'estimated_premium': product.estimatePremium(sumInsured),
      };

  Future<void> retryUpload(String uuid) => retry(Tables.quotations, uuid);
}

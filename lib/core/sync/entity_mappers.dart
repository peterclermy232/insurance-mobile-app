import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../utils/formatters.dart';

/// Translation between local rows and the /sync/ wire format.
class EntityMappers {
  EntityMappers._();

  /// Primary key name of each entity in server records.
  static const serverIdKey = {
    Tables.farmers: 'farmer_id',
    Tables.farms: 'farm_id',
    Tables.quotations: 'quotation_id',
    Tables.claims: 'claim_id',
    Tables.inspections: 'inspection_id',
  };

  static const referenceIdKey = {
    'crops': 'crop_id',
    'crop_varieties': 'crop_variety_id',
    'seasons': 'season_id',
    'insurance_products': 'product_id',
    'cover_types': 'cover_type_id',
    'product_categories': 'product_category_id',
  };

  static const singular = {
    Tables.farmers: 'farmer',
    Tables.farms: 'farm',
    Tables.quotations: 'quotation',
    Tables.claims: 'claim',
    Tables.inspections: 'inspection',
  };

  /// child table -> (local parent uuid column, local parent server id column,
  /// parent table, wire field name)
  static const _parents = {
    Tables.farms: ('farmer_uuid', 'farmer_server_id', Tables.farmers, 'farmer'),
    Tables.quotations: ('farm_uuid', 'farm_server_id', Tables.farms, 'farm'),
    Tables.claims: ('quotation_uuid', 'quotation_server_id', Tables.quotations, 'quotation'),
    Tables.inspections: ('farm_uuid', 'farm_server_id', Tables.farms, 'farm'),
  };

  // ------------------------------------------------------------- outbound

  static Future<Map<String, dynamic>> toPayload(
      DatabaseExecutor db, String table, Map<String, Object?> row) async {
    final out = <String, dynamic>{'client_uuid': row['client_uuid']};
    final parent = _parents[table];
    if (parent != null) out.addAll(await _parentRef(db, row, parent));

    switch (table) {
      case Tables.farmers:
        out.addAll({
          'first_name': row['first_name'],
          'last_name': row['last_name'],
          'id_number': row['id_number'],
          'phone_number': row['phone_number'],
          'email': _blankToNull(row['email']),
          'gender': _blankToNull(row['gender']),
          'date_of_birth': _blankToNull(row['date_of_birth']),
          'farmer_category': _blankToNull(row['farmer_category']),
          'next_of_kin': _decodeList(row['next_of_kin']),
          'bank_accounts': _decodeList(row['bank_accounts']),
        });
        _putCoord(out, 'registration_latitude', row['registration_latitude']);
        _putCoord(out, 'registration_longitude', row['registration_longitude']);
      case Tables.farms:
        out.addAll({
          'farm_name': row['farm_name'],
          'farm_size': (row['farm_size'] as num?)?.toStringAsFixed(2),
          'unit_of_measure': row['unit_of_measure'],
          'location_province': _blankToNull(row['location_province']),
          'location_district': _blankToNull(row['location_district']),
          'location_sector': _blankToNull(row['location_sector']),
          'administrative_unit': row['administrative_unit_id'],
          'location_unit': row['location_unit_id'],
          'village': _blankToNull(row['village']),
          'clan': _blankToNull(row['clan']),
          'status': row['status'] ?? 'ACTIVE',
        });
        _putCoord(out, 'latitude', row['latitude']);
        _putCoord(out, 'longitude', row['longitude']);
      case Tables.quotations:
        out.addAll({
          'insurance_product': row['insurance_product_id'],
          'sum_insured': (row['sum_insured'] as num?)?.toStringAsFixed(2),
        });
      case Tables.claims:
        out.addAll({
          'estimated_loss_amount': (row['estimated_loss_amount'] as num?)?.toStringAsFixed(2),
          'loss_details': decodeMap(row['loss_details']),
        });
      case Tables.inspections:
        out.addAll({
          'inspection_type': row['inspection_type'],
          'status': row['status'] ?? 'SCHEDULED',
          'scheduled_date': row['scheduled_date'],
          'scheduled_time': row['scheduled_time'],
          'completed_at': row['completed_at'],
          'check_in_time': row['check_in_time'],
          'check_out_time': row['check_out_time'],
          'findings': decodeMap(row['findings']),
          'recommendations': row['recommendations'] ?? '',
        });
        _putCoord(out, 'check_in_latitude', row['check_in_latitude']);
        _putCoord(out, 'check_in_longitude', row['check_in_longitude']);
        _putCoord(out, 'check_out_latitude', row['check_out_latitude']);
        _putCoord(out, 'check_out_longitude', row['check_out_longitude']);
    }
    // "Omit fields you don't have" - but keep explicit nulls for optional
    // fields so clearing them on the device reaches the server.
    final clearable = _clearable[table] ?? const <String>{};
    out.removeWhere((key, value) => value == null && !clearable.contains(key));
    return out;
  }

  /// Parent with a server id -> `farmer: 12`; captured on the device and not
  /// synced yet -> `farmer_uuid: "..."`.
  static Future<Map<String, Object?>> _parentRef(
      DatabaseExecutor db, Map<String, Object?> row, (String, String, String, String) parent) async {
    final (uuidColumn, serverIdColumn, parentTable, field) = parent;
    final parentUuid = row[uuidColumn] as String?;
    if (parentUuid != null) {
      final parents = await db.query(parentTable,
          columns: ['server_id'], where: 'client_uuid = ?', whereArgs: [parentUuid], limit: 1);
      if (parents.isNotEmpty) {
        final serverId = parents.first['server_id'];
        return serverId != null ? {field: serverId} : {'${field}_uuid': parentUuid};
      }
    }
    final serverId = row[serverIdColumn];
    if (serverId != null) return {field: serverId};
    return parentUuid != null ? {'${field}_uuid': parentUuid} : const {};
  }

  static void _putCoord(Map<String, dynamic> out, String key, Object? value) {
    if (value is num) out[key] = value.toStringAsFixed(6);
  }

  static const _clearable = {
    Tables.farmers: {'email', 'gender', 'date_of_birth', 'farmer_category'},
    Tables.farms: {'administrative_unit', 'location_unit', 'village', 'clan'},
  };

  static Object? _blankToNull(Object? value) =>
      (value is String && value.trim().isEmpty) ? null : value;

  // -------------------------------------------------------------- inbound

  /// Server record (serializer format) -> local column values. Parent uuids
  /// are looked up by server id; null when the parent isn't local yet.
  static Future<Map<String, Object?>> fromServer(
      DatabaseExecutor db, String table, Map<String, dynamic> r) async {
    final values = <String, Object?>{'server_updated_at': r['updated_at']};
    switch (table) {
      case Tables.farmers:
        values.addAll({
          'first_name': r['first_name'] ?? '',
          'last_name': r['last_name'] ?? '',
          'id_number': r['id_number'] ?? '',
          'phone_number': r['phone_number'] ?? '',
          'email': r['email'],
          'gender': r['gender'],
          'date_of_birth': r['date_of_birth'],
          'farmer_category': r['farmer_category']?.toString(),
          'registration_latitude': toDouble(r['registration_latitude']),
          'registration_longitude': toDouble(r['registration_longitude']),
          'photo_url': r['photo'],
          'status': r['status'],
          'next_of_kin': jsonEncode(_pick(r['next_of_kin'], const ['name', 'relationship', 'phone_number'])),
          'bank_accounts':
              jsonEncode(_pick(r['bank_accounts'], const ['bank_name', 'account_number', 'account_name'])),
        });
      case Tables.farms:
        values.addAll({
          'farmer_server_id': toServerId(r['farmer']),
          'farmer_uuid': await _uuidFor(db, Tables.farmers, r['farmer']),
          'farm_name': r['farm_name'] ?? '',
          'farm_size': toDouble(r['farm_size']),
          'unit_of_measure': r['unit_of_measure'],
          'location_province': r['location_province'],
          'location_district': r['location_district'],
          'location_sector': r['location_sector'],
          'administrative_unit_id': toInt(r['administrative_unit']),
          'location_unit_id': toInt(r['location_unit']),
          'village': r['village'],
          'clan': r['clan'],
          'latitude': toDouble(r['latitude']),
          'longitude': toDouble(r['longitude']),
          'status': r['status'],
        });
      case Tables.quotations:
        values.addAll({
          'farm_server_id': toServerId(r['farm']),
          'farm_uuid': await _uuidFor(db, Tables.farms, r['farm']),
          'farmer_server_id': toServerId(r['farmer']),
          'insurance_product_id': toServerId(r['insurance_product']),
          'product_name': r['product_name'],
          'sum_insured': toDouble(r['sum_insured']),
          'premium_amount': toDouble(r['premium_amount']),
          'policy_number': r['policy_number'],
          'status': r['status'],
          'quotation_date': r['quotation_date'],
        });
      case Tables.claims:
        final details = r['loss_details'];
        values.addAll({
          'quotation_server_id': toServerId(r['quotation']),
          'quotation_uuid': await _uuidFor(db, Tables.quotations, r['quotation']),
          'farmer_server_id': toServerId(r['farmer']),
          'claim_number': r['claim_number'],
          'estimated_loss_amount': toDouble(r['estimated_loss_amount']),
          'approved_amount': toDouble(r['approved_amount']),
          'status': r['status'],
          'loss_details': details is String ? details : jsonEncode(details ?? const {}),
          'claim_date': r['claim_date'],
          'assessor_name': r['assessor_name'],
        });
      case Tables.inspections:
        final findings = r['findings'];
        values.addAll({
          'farm_server_id': toServerId(r['farm']),
          'farm_uuid': await _uuidFor(db, Tables.farms, r['farm']),
          'inspection_type': r['inspection_type'] ?? 'PRE_PLANTING',
          'status': r['status'],
          'scheduled_date': r['scheduled_date'],
          'scheduled_time': r['scheduled_time'],
          'completed_at': r['completed_at'],
          'check_in_latitude': toDouble(r['check_in_latitude']),
          'check_in_longitude': toDouble(r['check_in_longitude']),
          'check_in_time': r['check_in_time'],
          'check_out_latitude': toDouble(r['check_out_latitude']),
          'check_out_longitude': toDouble(r['check_out_longitude']),
          'check_out_time': r['check_out_time'],
          'findings': findings is String ? findings : jsonEncode(findings ?? const {}),
          'recommendations': r['recommendations'],
          'inspector_name': r['inspector_name'],
        });
    }
    // An unresolved parent must never clear an existing local link.
    values.removeWhere((key, value) => value == null && key.endsWith('_uuid'));
    return values;
  }

  static Future<String?> _uuidFor(DatabaseExecutor db, String table, Object? serverId) async {
    final id = toServerId(serverId);
    if (id == null) return null;
    final rows = await db.query(table,
        columns: ['client_uuid'], where: 'server_id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first['client_uuid'] as String?;
  }

  static List<Map<String, Object?>> _pick(Object? list, List<String> keys) {
    if (list is! List) return const [];
    return [
      for (final item in list.whereType<Map>()) {for (final k in keys) k: item[k] ?? ''}
    ];
  }

  /// Fills parent uuids that couldn't be resolved while applying (parent
  /// arrived later in the same response).
  static Future<void> relinkParents(DatabaseExecutor db) async {
    for (final entry in _parents.entries) {
      final (uuidColumn, serverIdColumn, parentTable, _) = entry.value;
      await db.execute('''
        UPDATE ${entry.key} SET $uuidColumn =
          (SELECT p.client_uuid FROM $parentTable p WHERE p.server_id = ${entry.key}.$serverIdColumn)
        WHERE $uuidColumn IS NULL AND $serverIdColumn IS NOT NULL
      ''');
    }
  }

  /// Changes a row's client_uuid and every local reference to it.
  static Future<void> rekey(DatabaseExecutor db, String table, String from, String to) async {
    await db.update(table, {'client_uuid': to}, where: 'client_uuid = ?', whereArgs: [from]);
    for (final entry in _parents.entries) {
      final (uuidColumn, _, parentTable, _) = entry.value;
      if (parentTable == table) {
        await db.update(entry.key, {uuidColumn: to}, where: '$uuidColumn = ?', whereArgs: [from]);
      }
    }
    await db.update(Tables.media, {'entity_uuid': to}, where: 'entity_uuid = ?', whereArgs: [from]);
  }
}

List<Map<String, dynamic>> _decodeList(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final value = jsonDecode(raw);
    return value is List ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];
  } catch (_) {
    return const [];
  }
}

Map<String, dynamic> decodeMap(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is! String || raw.isEmpty) return {};
  try {
    final value = jsonDecode(raw);
    return value is Map ? value.cast<String, dynamic>() : {};
  } catch (_) {
    return {};
  }
}

List<Map<String, dynamic>> decodeList(Object? raw) => _decodeList(raw);

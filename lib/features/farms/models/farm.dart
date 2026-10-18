import '../../../core/db/syncable.dart';

class Farm {
  const Farm({
    this.uuid,
    this.sync = const SyncInfo(status: 'pending'),
    required this.farmerUuid,
    required this.name,
    this.size,
    this.unit = 'ACRES',
    this.county,
    this.subCounty,
    this.ward,
    this.administrativeUnitId,
    this.unitName,
    this.locationUnitId,
    this.locationUnitName,
    this.village,
    this.clan,
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    this.status,
    this.farmerName,
  });

  factory Farm.fromRow(Map<String, Object?> r) => Farm(
        uuid: r['client_uuid'] as String,
        sync: SyncInfo.fromRow(r),
        farmerUuid: r['farmer_uuid'] as String?,
        name: r['farm_name'] as String? ?? '',
        size: (r['farm_size'] as num?)?.toDouble(),
        unit: r['unit_of_measure'] as String? ?? 'ACRES',
        county: r['location_province'] as String?,
        subCounty: r['location_district'] as String?,
        ward: r['location_sector'] as String?,
        administrativeUnitId: r['administrative_unit_id'] as int?,
        unitName: r['unit_name'] as String?,
        locationUnitId: r['location_unit_id'] as int?,
        locationUnitName: r['location_unit_name'] as String?,
        village: r['village'] as String?,
        clan: r['clan'] as String?,
        latitude: (r['latitude'] as num?)?.toDouble(),
        longitude: (r['longitude'] as num?)?.toDouble(),
        gpsAccuracy: (r['gps_accuracy'] as num?)?.toDouble(),
        status: r['status'] as String?,
        farmerName: r['farmer_name'] as String?,
      );

  final String? uuid;
  final SyncInfo sync;
  final String? farmerUuid;
  final String name;
  final double? size;
  final String unit;

  /// Free-text location used before the location tree existed (and when the
  /// device has no locations downloaded). Kenya: County -> location_province,
  /// Sub-county -> location_district, Ward -> location_sector.
  final String? county;
  final String? subCounty;
  final String? ward;

  /// Deepest unit picked in each branch of the location tree, and its name (from a join):
  /// county government (sub-county / ward) and national government (location / sub-location).
  final int? administrativeUnitId;
  final String? unitName;
  final int? locationUnitId;
  final String? locationUnitName;
  final String? village;
  final String? clan;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;
  final String? status;
  final String? farmerName;

  static const units = {'ACRES': 'Acres', 'HECTARES': 'Hectares'};

  String get sizeLabel {
    if (size == null) return '-';
    final n = size! == size!.roundToDouble() ? size!.toStringAsFixed(0) : size!.toStringAsFixed(2);
    return '$n ${(units[unit] ?? unit).toLowerCase()}';
  }

  String get locationLabel => [
        village,
        ...(unitName != null || locationUnitName != null
            ? [locationUnitName, unitName]
            : [ward, subCounty, county]),
      ]
      .where((e) => e != null && e.trim().isNotEmpty)
      .join(', ');

  Map<String, Object?> toColumns() => {
        'farmer_uuid': farmerUuid,
        'farm_name': name.trim(),
        'farm_size': size,
        'unit_of_measure': unit,
        'location_province': county?.trim(),
        'location_district': subCounty?.trim(),
        'location_sector': ward?.trim(),
        'administrative_unit_id': administrativeUnitId,
        'location_unit_id': locationUnitId,
        'village': village?.trim(),
        'clan': clan?.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'gps_accuracy': gpsAccuracy,
        'status': status ?? 'ACTIVE',
      };
}

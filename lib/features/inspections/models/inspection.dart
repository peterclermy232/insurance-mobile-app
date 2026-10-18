import '../../../core/db/syncable.dart';
import '../../../core/sync/entity_mappers.dart';
import '../../../core/utils/formatters.dart';

class Inspection {
  const Inspection({
    this.uuid,
    this.sync = const SyncInfo(status: 'pending'),
    required this.farmUuid,
    required this.type,
    this.status = 'SCHEDULED',
    this.scheduledDate,
    this.scheduledTime,
    this.completedAt,
    this.checkInLat,
    this.checkInLon,
    this.checkInTime,
    this.checkOutLat,
    this.checkOutLon,
    this.checkOutTime,
    this.findings = const {},
    this.recommendations = '',
    this.inspectorName,
    this.farmName,
    this.farmerName,
  });

  factory Inspection.fromRow(Map<String, Object?> r) => Inspection(
        uuid: r['client_uuid'] as String,
        sync: SyncInfo.fromRow(r),
        farmUuid: r['farm_uuid'] as String?,
        type: r['inspection_type'] as String? ?? 'PRE_PLANTING',
        status: r['status'] as String? ?? 'SCHEDULED',
        scheduledDate: r['scheduled_date'] as String?,
        scheduledTime: r['scheduled_time'] as String?,
        completedAt: DateTime.tryParse(r['completed_at'] as String? ?? ''),
        checkInLat: (r['check_in_latitude'] as num?)?.toDouble(),
        checkInLon: (r['check_in_longitude'] as num?)?.toDouble(),
        checkInTime: DateTime.tryParse(r['check_in_time'] as String? ?? ''),
        checkOutLat: (r['check_out_latitude'] as num?)?.toDouble(),
        checkOutLon: (r['check_out_longitude'] as num?)?.toDouble(),
        checkOutTime: DateTime.tryParse(r['check_out_time'] as String? ?? ''),
        findings: decodeMap(r['findings']),
        recommendations: r['recommendations'] as String? ?? '',
        inspectorName: r['inspector_name'] as String?,
        farmName: r['farm_name'] as String?,
        farmerName: r['farmer_name'] as String?,
      );

  static const types = {
    'PRE_PLANTING': 'Pre-planting',
    'MID_SEASON': 'Mid-season',
    'PRE_HARVEST': 'Pre-harvest',
    'LOSS_ASSESSMENT': 'Loss assessment',
  };

  static const cropConditions = ['Excellent', 'Good', 'Fair', 'Poor', 'Failed'];

  final String? uuid;
  final SyncInfo sync;
  final String? farmUuid;
  final String type;

  /// SCHEDULED -> IN_PROGRESS (checked in) -> COMPLETED (checked out).
  final String status;
  final String? scheduledDate;
  final String? scheduledTime;
  final DateTime? completedAt;
  final double? checkInLat;
  final double? checkInLon;
  final DateTime? checkInTime;
  final double? checkOutLat;
  final double? checkOutLon;
  final DateTime? checkOutTime;

  /// {crop_condition, damage_percent, notes}
  final Map<String, dynamic> findings;
  final String recommendations;
  final String? inspectorName;
  final String? farmName;
  final String? farmerName;

  String get typeLabel => types[type] ?? Fmt.enumLabel(type);
  String get statusLabel => Fmt.enumLabel(status);

  bool get isCheckedIn => checkInTime != null;
  bool get isCheckedOut => checkOutTime != null;
  bool get isEditable => sync.canEditFromDevice && status != 'COMPLETED' && status != 'CANCELLED';

  String? get cropCondition => findings['crop_condition'] as String?;
  int? get damagePercent => toInt(findings['damage_percent']);
  String get notes => '${findings['notes'] ?? ''}';

  Map<String, Object?> toColumns() => {
        'farm_uuid': farmUuid,
        'inspection_type': type,
        'status': status,
        'scheduled_date': scheduledDate,
        'scheduled_time': scheduledTime,
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'check_in_latitude': checkInLat,
        'check_in_longitude': checkInLon,
        'check_in_time': checkInTime?.toUtc().toIso8601String(),
        'check_out_latitude': checkOutLat,
        'check_out_longitude': checkOutLon,
        'check_out_time': checkOutTime?.toUtc().toIso8601String(),
        'findings': findings,
        'recommendations': recommendations,
      };
}

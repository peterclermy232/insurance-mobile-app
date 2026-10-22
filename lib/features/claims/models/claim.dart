import '../../../core/db/syncable.dart';
import '../../../core/sync/entity_mappers.dart';
import '../../../core/utils/formatters.dart';

class Claim {
  const Claim({
    this.uuid,
    this.sync = const SyncInfo(status: 'pending'),
    required this.quotationUuid,
    required this.estimatedLoss,
    required this.cause,
    this.description = '',
    this.dateOfLoss,
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    this.claimNumber,
    this.approvedAmount,
    this.status,
    this.claimDate,
    this.assessorName,
    this.policyNumber,
    this.productName,
    this.sumInsured,
    this.farmName,
    this.farmerName,
    this.farmerUuid,
    this.createdAt,
    this.areaYield,
  });

  factory Claim.fromRow(Map<String, Object?> r) {
    final details = decodeMap(r['loss_details']);
    final location = details['location'];
    return Claim(
      uuid: r['client_uuid'] as String,
      sync: SyncInfo.fromRow(r),
      quotationUuid: r['quotation_uuid'] as String?,
      estimatedLoss: (r['estimated_loss_amount'] as num?)?.toDouble() ?? 0,
      cause: '${details['cause'] ?? ''}',
      description: '${details['description'] ?? ''}',
      dateOfLoss: details['date_of_loss'] as String?,
      latitude: location is Map ? toDouble(location['latitude']) : null,
      longitude: location is Map ? toDouble(location['longitude']) : null,
      gpsAccuracy: location is Map ? toDouble(location['accuracy']) : null,
      claimNumber: r['claim_number'] as String?,
      approvedAmount: (r['approved_amount'] as num?)?.toDouble(),
      status: r['status'] as String?,
      claimDate: DateTime.tryParse(r['claim_date'] as String? ?? ''),
      assessorName: r['assessor_name'] as String?,
      policyNumber: r['policy_number'] as String?,
      productName: r['product_name'] as String?,
      sumInsured: (r['sum_insured'] as num?)?.toDouble(),
      farmName: r['farm_name'] as String?,
      farmerName: r['farmer_name'] as String?,
      farmerUuid: r['farmer_uuid'] as String?,
      createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
      areaYield: AreaYieldPayout.fromDetails(details),
    );
  }

  static const causes = ['Drought', 'Flood', 'Pests', 'Disease', 'Hail', 'Fire', 'Other'];

  final String? uuid;
  final SyncInfo sync;
  final String? quotationUuid;
  final double estimatedLoss;
  final String cause;
  final String description;
  final String? dateOfLoss;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;
  final String? claimNumber;
  final double? approvedAmount;
  final String? status;
  final DateTime? claimDate;
  final String? assessorName;
  final String? policyNumber;
  final String? productName;
  final double? sumInsured;
  final String? farmName;
  final String? farmerName;
  final String? farmerUuid;
  final DateTime? createdAt;

  /// Set on claims the server created from an approved area yield.
  final AreaYieldPayout? areaYield;

  bool get isAreaYield => areaYield != null;

  /// The server assigns the claim number on first sync.
  String get numberLabel => (claimNumber == null || claimNumber!.isEmpty) ? 'Pending' : claimNumber!;

  String get statusLabel => status == null ? 'Awaiting sync' : Fmt.enumLabel(status);

  /// The office owns claims once they leave OPEN.
  bool get isEditable => sync.canEditFromDevice && (status == null || status == 'OPEN') && !isAreaYield;

  Map<String, Object?> lossDetails() => {
        'cause': cause,
        'description': description.trim(),
        if (dateOfLoss != null) 'date_of_loss': dateOfLoss,
        if (latitude != null && longitude != null)
          'location': {
            'latitude': double.parse(latitude!.toStringAsFixed(6)),
            'longitude': double.parse(longitude!.toStringAsFixed(6)),
            if (gpsAccuracy != null) 'accuracy': gpsAccuracy!.round(),
          },
      };
}

/// The calculation stored in loss_details of an area yield claim.
class AreaYieldPayout {
  const AreaYieldPayout({
    this.area,
    this.areaLevel,
    this.yieldUnit,
    this.expectedYield,
    this.coverageLevel,
    this.guaranteedYield,
    this.actualYield,
    this.payoutPercent,
    this.payout,
  });

  static AreaYieldPayout? fromDetails(Map<String, dynamic> d) {
    if (d['calculation_method'] != 'AREA_YIELD') return null;
    return AreaYieldPayout(
      area: d['area']?.toString(),
      areaLevel: d['area_level']?.toString(),
      yieldUnit: d['yield_unit']?.toString(),
      expectedYield: toDouble(d['expected_yield']),
      coverageLevel: toDouble(d['coverage_level']),
      guaranteedYield: toDouble(d['guaranteed_yield']),
      actualYield: toDouble(d['actual_yield']),
      payoutPercent: toDouble(d['payout_percent']),
      payout: toDouble(d['payout']),
    );
  }

  final String? area;
  final String? areaLevel;
  final String? yieldUnit;
  final double? expectedYield;
  final double? coverageLevel;
  final double? guaranteedYield;
  final double? actualYield;
  final double? payoutPercent;
  final double? payout;

  /// "12.50 bags/acre"
  String? yieldLabel(double? value) =>
      value == null ? null : '${value.toStringAsFixed(2)}${yieldUnit == null ? '' : ' $yieldUnit'}';

  String? get payoutPercentLabel => payoutPercent == null ? null : '${payoutPercent!.toStringAsFixed(2)}%';
}

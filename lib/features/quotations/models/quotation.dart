import '../../../core/db/syncable.dart';
import '../../../core/utils/formatters.dart';

/// How a cover type works out what to pay (`calculation_method` from the server).
class CalculationMethod {
  CalculationMethod._();

  static const individualFarm = 'INDIVIDUAL_FARM';

  /// Paid from the average yield of the farm's ward / sub-county / county; the
  /// server creates the claims itself, so they are never reported on the device.
  static const areaYield = 'AREA_YIELD';
  static const weatherIndex = 'WEATHER_INDEX';

  /// "ward", "sub-county", "county" (same wording as the server's notice).
  static String areaLabel(String? areaLevel) => switch (areaLevel) {
        'WARD' => 'ward',
        'SUB_COUNTY' => 'sub-county',
        'COUNTY' => 'county',
        _ => 'area',
      };

  /// Explanation of basis risk to read to the farmer before selling area yield cover.
  static String basisRiskNotice(String? areaLevel) {
    final area = areaLabel(areaLevel);
    return 'Payouts are based on the average yield of the whole $area, not on your own farm. '
        'You may get no payout after a poor harvest on your farm if the $area average is good, '
        'and you may get a payout after a good harvest if the $area average is poor.';
  }

  static const noClaimNeeded =
      "Area yield policies are paid automatically from the area's measured yield - no claim needed.";
}

class InsuranceProduct {
  const InsuranceProduct({
    required this.id,
    required this.name,
    required this.premiumRate,
    this.cropName,
    this.varietyName,
    this.seasonName,
    this.categoryName,
    this.defaultSumInsured,
    this.status,
    this.calculationMethod,
    this.coverTypeName,
    this.areaLevel,
    this.coverageLevel,
    this.yieldUnit,
    this.maxPayoutPercent,
  });

  factory InsuranceProduct.fromJson(Map<String, dynamic> j) => InsuranceProduct(
        id: toServerId(j['product_id']) ?? '',
        name: '${j['product_name'] ?? 'Product ${j['product_id']}'}',
        premiumRate: toDouble(j['average_premium_rate']) ?? 0,
        cropName: j['crop_name'] as String?,
        varietyName: j['crop_variety_name'] as String?,
        seasonName: j['season_name'] as String?,
        categoryName: j['product_category_name'] as String?,
        defaultSumInsured: toDouble(j['sum_insured']),
        status: j['status'] as String?,
        calculationMethod: j['calculation_method'] as String?,
        coverTypeName: j['cover_type_name'] as String?,
        areaLevel: j['area_level'] as String?,
        coverageLevel: toDouble(j['coverage_level']),
        yieldUnit: j['yield_unit'] as String?,
        maxPayoutPercent: toDouble(j['max_payout_percent']),
      );

  final String id;
  final String name;

  /// Percent of sum insured.
  final double premiumRate;
  final String? cropName;
  final String? varietyName;
  final String? seasonName;
  final String? categoryName;
  final double? defaultSumInsured;
  final String? status;

  /// INDIVIDUAL_FARM / AREA_YIELD / WEATHER_INDEX (see [CalculationMethod]).
  final String? calculationMethod;
  final String? coverTypeName;

  /// Area yield only: WARD / SUB_COUNTY / COUNTY the payout is measured over.
  final String? areaLevel;

  /// Area yield only: percent of the area's expected yield that is guaranteed.
  final double? coverageLevel;
  final String? yieldUnit;

  /// Percent of the sum insured paid at most.
  final double? maxPayoutPercent;

  bool get isAreaYield => calculationMethod == CalculationMethod.areaYield;

  String get areaLabel => CalculationMethod.areaLabel(areaLevel);

  String get basisRiskNotice => CalculationMethod.basisRiskNotice(areaLevel);

  /// e.g. "Covers 70% of the ward's expected yield (bags/acre). Pays at most 80% of the sum insured."
  String? get coverageTerms {
    final parts = <String>[
      if (coverageLevel != null)
        "Covers ${_percent(coverageLevel!)} of the $areaLabel's expected yield"
            "${yieldUnit == null || yieldUnit!.isEmpty ? '' : ' ($yieldUnit)'}.",
      if (maxPayoutPercent != null && maxPayoutPercent! < 100)
        'Pays at most ${_percent(maxPayoutPercent!)} of the sum insured.',
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  static String _percent(double v) => '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}%';

  bool get isActive => status == null || status == 'ACTIVE';

  String get cropSeasonLabel => [
        if (cropName != null) varietyName != null ? '$cropName ($varietyName)' : cropName,
        if (seasonName != null) seasonName,
      ].join(' - ');

  /// sum_insured x average_premium_rate / 100, same formula as the server.
  double estimatePremium(double sumInsured) =>
      ((sumInsured * premiumRate / 100) * 100).roundToDouble() / 100;
}

class Quotation {
  const Quotation({
    this.uuid,
    this.sync = const SyncInfo(status: 'pending'),
    required this.farmUuid,
    required this.productId,
    required this.sumInsured,
    this.productName,
    this.premiumAmount,
    this.estimatedPremium,
    this.policyNumber,
    this.status,
    this.quotationDate,
    this.farmName,
    this.farmerName,
    this.farmerUuid,
    this.createdAt,
    this.calculationMethod,
    this.basisRiskNotice,
  });

  factory Quotation.fromRow(Map<String, Object?> r) => Quotation(
        uuid: r['client_uuid'] as String,
        sync: SyncInfo.fromRow(r),
        farmUuid: r['farm_uuid'] as String?,
        productId: toServerId(r['insurance_product_id']),
        sumInsured: (r['sum_insured'] as num?)?.toDouble() ?? 0,
        productName: r['product_name'] as String?,
        premiumAmount: (r['premium_amount'] as num?)?.toDouble(),
        estimatedPremium: (r['estimated_premium'] as num?)?.toDouble(),
        policyNumber: r['policy_number'] as String?,
        status: r['status'] as String?,
        quotationDate: DateTime.tryParse(r['quotation_date'] as String? ?? ''),
        farmName: r['farm_name'] as String?,
        farmerName: r['farmer_name'] as String?,
        farmerUuid: r['farmer_uuid'] as String?,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        calculationMethod: r['calculation_method'] as String?,
        basisRiskNotice: r['basis_risk_notice'] as String?,
      );

  final String? uuid;
  final SyncInfo sync;
  final String? farmUuid;
  final String? productId;
  final double sumInsured;
  final String? productName;
  final double? premiumAmount;
  final double? estimatedPremium;
  final String? policyNumber;

  /// Server status (OPEN, WRITTEN, PAID, ...); null until first sync.
  final String? status;
  final DateTime? quotationDate;
  final String? farmName;
  final String? farmerName;
  final String? farmerUuid;
  final DateTime? createdAt;

  /// From the server, or from the product when the quotation was captured on
  /// this device (see [CalculationMethod]).
  final String? calculationMethod;
  final String? basisRiskNotice;

  /// Paid automatically from the area's yield; never claimed individually.
  bool get isAreaYield => calculationMethod == CalculationMethod.areaYield;

  /// Claims may only be reported on written or paid policies, and never on
  /// area yield policies (the server creates those claims itself).
  bool get isClaimable => sync.serverId != null && (status == 'WRITTEN' || status == 'PAID') && !isAreaYield;

  /// The office owns quotations once they leave OPEN/DRAFT.
  bool get isEditable =>
      sync.canEditFromDevice && (status == null || status == 'OPEN' || status == 'DRAFT');

  String get statusLabel => status == null ? 'Awaiting sync' : Fmt.enumLabel(status);

  String get title => policyNumber?.isNotEmpty == true ? policyNumber! : (productName ?? 'Quotation');
}

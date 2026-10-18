import '../../../core/db/syncable.dart';
import '../../../core/utils/formatters.dart';

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

  /// Claims may only be reported on written or paid policies.
  bool get isClaimable => sync.serverId != null && (status == 'WRITTEN' || status == 'PAID');

  /// The office owns quotations once they leave OPEN/DRAFT.
  bool get isEditable =>
      sync.canEditFromDevice && (status == null || status == 'OPEN' || status == 'DRAFT');

  String get statusLabel => status == null ? 'Awaiting sync' : Fmt.enumLabel(status);

  String get title => policyNumber?.isNotEmpty == true ? policyNumber! : (productName ?? 'Quotation');
}

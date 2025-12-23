import 'dart:convert';

class Claim {
  final int? id; // local SQLite ID
  final int farmerId;
  final int? serverId; // backend ID
  final String? claimNumber;
  final int quotationId;
  final double estimatedLossAmount;
  final String assessorNotes;
  final String lossDetails;
  final List<String> photos;
  final double? latitude;
  final double? longitude;
  final String syncStatus; // pending | synced | error
  final int createdAt;
  final int updatedAt;

  Claim({
    this.id,
    required this.farmerId,
    this.serverId,
    this.claimNumber,
    required this.quotationId,
    required this.estimatedLossAmount,
    required this.assessorNotes,
    required this.lossDetails,
    required this.photos,
    this.latitude,
    this.longitude,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 🗄️ From SQLite Map
  factory Claim.fromMap(Map<String, dynamic> map) {
    return Claim(
      id: map['id'] as int?,
      farmerId: map['farmer_id'] as int,
      serverId: map['server_id'] as int?,
      claimNumber: map['claim_number'] as String?,
      quotationId: map['quotation_id'] as int,
      estimatedLossAmount:
      (map['estimated_loss_amount'] as num).toDouble(),
      assessorNotes: map['assessor_notes'] ?? '',
      lossDetails: map['loss_details'] ?? '',
      photos: map['photos'] != null
          ? List<String>.from(jsonDecode(map['photos']))
          : [],
      latitude: map['latitude'] != null
          ? (map['latitude'] as num).toDouble()
          : null,
      longitude: map['longitude'] != null
          ? (map['longitude'] as num).toDouble()
          : null,
      syncStatus: map['sync_status'] ?? 'pending',
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }

  /// 🗄️ To SQLite Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farmer_id': farmerId,
      'server_id': serverId,
      'claim_number': claimNumber,
      'quotation_id': quotationId,
      'estimated_loss_amount': estimatedLossAmount,
      'assessor_notes': assessorNotes,
      'loss_details': lossDetails,
      'photos': jsonEncode(photos),
      'latitude': latitude,
      'longitude': longitude,
      'sync_status': syncStatus,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 🌐 API payload (matches your Django endpoint)
  Map<String, dynamic> toApiPayload({required int farmerServerId}) {
    return {
      'farmer': farmerServerId,
      'quotation': quotationId,
      'estimated_loss_amount': estimatedLossAmount,
      'loss_details': lossDetails,
      'status': 'OPEN',
    };
  }

  /// 🔁 Copy helper (for updates)
  Claim copyWith({
    int? id,
    int? farmerId,
    int? serverId,
    String? claimNumber,
    int? quotationId,
    double? estimatedLossAmount,
    String? assessorNotes,
    String? lossDetails,
    List<String>? photos,
    double? latitude,
    double? longitude,
    String? syncStatus,
    int? createdAt,
    int? updatedAt,
  }) {
    return Claim(
      id: id ?? this.id,
      farmerId: farmerId ?? this.farmerId,
      serverId: serverId ?? this.serverId,
      claimNumber: claimNumber ?? this.claimNumber,
      quotationId: quotationId ?? this.quotationId,
      estimatedLossAmount:
      estimatedLossAmount ?? this.estimatedLossAmount,
      assessorNotes: assessorNotes ?? this.assessorNotes,
      lossDetails: lossDetails ?? this.lossDetails,
      photos: photos ?? this.photos,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

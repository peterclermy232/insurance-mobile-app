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
  final String status; // OPEN, PROCESSING, APPROVED, REJECTED

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
    this.status = 'OPEN',
  });

  /// 🗄️ From SQLite Map
  factory Claim.fromMap(Map<String, dynamic> map) {
    return Claim(
      id: map['id'] as int?,
      farmerId: map['farmer_id'] as int,
      serverId: map['server_id'] as int?,
      claimNumber: map['claim_number'] as String?,
      quotationId: map['quotation_id'] as int,
      estimatedLossAmount: (map['estimated_loss_amount'] as num).toDouble(),
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
      status: map['status'] ?? 'OPEN',
    );
  }

  /// 🗄️ To SQLite Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
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
      'status': status,
    };
  }

  /// 🌐 From API JSON response
  factory Claim.fromJson(Map<String, dynamic> json) {
    return Claim(
      id: json['id'] as int?,
      farmerId: json['farmer_id'] as int? ?? json['farmer'] as int,
      serverId: json['server_id'] as int? ?? json['claim_id'] as int?,
      claimNumber: json['claim_number'] as String?,
      quotationId: json['quotation_id'] as int? ?? json['quotation'] as int? ?? 1,
      estimatedLossAmount: (json['estimated_loss_amount'] as num).toDouble(),
      assessorNotes: json['assessor_notes'] ?? '',
      lossDetails: json['loss_details'] ?? '',
      photos: json['photos'] != null
          ? (json['photos'] is String
          ? List<String>.from(jsonDecode(json['photos']))
          : List<String>.from(json['photos']))
          : [],
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      syncStatus: json['sync_status'] ?? 'pending',
      createdAt: json['created_at'] is int
          ? json['created_at']
          : DateTime.parse(json['created_at']).millisecondsSinceEpoch,
      updatedAt: json['updated_at'] is int
          ? json['updated_at']
          : DateTime.parse(json['updated_at']).millisecondsSinceEpoch,
      status: json['status'] ?? 'OPEN',
    );
  }

  /// 🌐 To API JSON
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'farmer_id': farmerId,
      'server_id': serverId,
      'claim_number': claimNumber,
      'quotation_id': quotationId,
      'estimated_loss_amount': estimatedLossAmount,
      'assessor_notes': assessorNotes,
      'loss_details': lossDetails,
      'photos': photos,
      'latitude': latitude,
      'longitude': longitude,
      'sync_status': syncStatus,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'status': status,
    };
  }

  /// 🌐 API payload (matches Django endpoint)
  Map<String, dynamic> toApiPayload({required int farmerServerId}) {
    return {
      'farmer': farmerServerId,
      'quotation': quotationId,
      'estimated_loss_amount': estimatedLossAmount,
      'loss_details': lossDetails,
      'status': status,
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
    String? status,
  }) {
    return Claim(
      id: id ?? this.id,
      farmerId: farmerId ?? this.farmerId,
      serverId: serverId ?? this.serverId,
      claimNumber: claimNumber ?? this.claimNumber,
      quotationId: quotationId ?? this.quotationId,
      estimatedLossAmount: estimatedLossAmount ?? this.estimatedLossAmount,
      assessorNotes: assessorNotes ?? this.assessorNotes,
      lossDetails: lossDetails ?? this.lossDetails,
      photos: photos ?? this.photos,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
    );
  }
}
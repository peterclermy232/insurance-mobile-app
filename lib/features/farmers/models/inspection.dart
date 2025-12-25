class Inspection {
  final int? id;
  final int farmId;
  final int inspectorId;
  final String inspectionType;
  final String status;
  final DateTime scheduledDate;
  final DateTime? completedAt;

  // GPS tracking
  final double? checkInLatitude;
  final double? checkInLongitude;
  final DateTime? checkInTime;
  final double? checkOutLatitude;
  final double? checkOutLongitude;
  final DateTime? checkOutTime;

  // Findings
  final Map<String, dynamic> findings;
  final String? recommendations;
  final bool synced;

  Inspection({
    this.id,
    required this.farmId,
    required this.inspectorId,
    required this.inspectionType,
    this.status = 'SCHEDULED',
    required this.scheduledDate,
    this.completedAt,
    this.checkInLatitude,
    this.checkInLongitude,
    this.checkInTime,
    this.checkOutLatitude,
    this.checkOutLongitude,
    this.checkOutTime,
    this.findings = const {},
    this.recommendations,
    this.synced = false,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'farm_id': farmId,
      'inspector_id': inspectorId,
      'inspection_type': inspectionType,
      'status': status,
      'scheduled_date': scheduledDate.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'check_in_latitude': checkInLatitude,
      'check_in_longitude': checkInLongitude,
      'check_in_time': checkInTime?.toIso8601String(),
      'check_out_latitude': checkOutLatitude,
      'check_out_longitude': checkOutLongitude,
      'check_out_time': checkOutTime?.toIso8601String(),
      'findings': findings,
      'recommendations': recommendations,
      'synced': synced ? 1 : 0,
    };
  }

  factory Inspection.fromJson(Map<String, dynamic> json) {
    return Inspection(
      id: json['id'] ?? json['inspection_id'],
      farmId: json['farm_id'],
      inspectorId: json['inspector_id'],
      inspectionType: json['inspection_type'],
      status: json['status'] ?? 'SCHEDULED',
      scheduledDate: DateTime.parse(json['scheduled_date']),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      checkInLatitude: json['check_in_latitude'] != null
          ? double.parse(json['check_in_latitude'].toString())
          : null,
      checkInLongitude: json['check_in_longitude'] != null
          ? double.parse(json['check_in_longitude'].toString())
          : null,
      checkInTime: json['check_in_time'] != null
          ? DateTime.parse(json['check_in_time'])
          : null,
      checkOutLatitude: json['check_out_latitude'] != null
          ? double.parse(json['check_out_latitude'].toString())
          : null,
      checkOutLongitude: json['check_out_longitude'] != null
          ? double.parse(json['check_out_longitude'].toString())
          : null,
      checkOutTime: json['check_out_time'] != null
          ? DateTime.parse(json['check_out_time'])
          : null,
      findings: json['findings'] ?? {},
      recommendations: json['recommendations'],
      synced: json['synced'] == 1,
    );
  }

  Inspection copyWith({
    int? id,
    String? status,
    DateTime? completedAt,
    double? checkInLatitude,
    double? checkInLongitude,
    DateTime? checkInTime,
    double? checkOutLatitude,
    double? checkOutLongitude,
    DateTime? checkOutTime,
    Map<String, dynamic>? findings,
    String? recommendations,
  }) {
    return Inspection(
      id: id ?? this.id,
      farmId: farmId,
      inspectorId: inspectorId,
      inspectionType: inspectionType,
      status: status ?? this.status,
      scheduledDate: scheduledDate,
      completedAt: completedAt ?? this.completedAt,
      checkInLatitude: checkInLatitude ?? this.checkInLatitude,
      checkInLongitude: checkInLongitude ?? this.checkInLongitude,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutLatitude: checkOutLatitude ?? this.checkOutLatitude,
      checkOutLongitude: checkOutLongitude ?? this.checkOutLongitude,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      findings: findings ?? this.findings,
      recommendations: recommendations ?? this.recommendations,
      synced: synced,
    );
  }
}

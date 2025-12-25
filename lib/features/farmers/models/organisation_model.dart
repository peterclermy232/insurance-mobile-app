class Organisation {
  final int organisationId;
  final String organisationName;
  final String organisationCode;
  final String? organisationEmail;
  final String? organisationPhone;
  final String status;

  Organisation({
    required this.organisationId,
    required this.organisationName,
    required this.organisationCode,
    this.organisationEmail,
    this.organisationPhone,
    this.status = 'ACTIVE',
  });

  factory Organisation.fromJson(Map<String, dynamic> json) {
    return Organisation(
      organisationId: json['organisation_id'] as int,
      organisationName: json['organisation_name'] as String,
      organisationCode: json['organisation_code'] as String,
      organisationEmail: json['organisation_email'] as String?,
      organisationPhone: json['organisation_msisdn'] as String?,
      status: json['organisation_status'] as String? ?? 'ACTIVE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'organisation_id': organisationId,
      'organisation_name': organisationName,
      'organisation_code': organisationCode,
      'organisation_email': organisationEmail,
      'organisation_msisdn': organisationPhone,
      'organisation_status': status,
    };
  }

  @override
  String toString() => organisationName;
}
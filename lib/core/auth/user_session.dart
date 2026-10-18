import '../config/app_config.dart';

/// The signed-in field officer, as returned by /auth/login/ (`user`).
class UserSession {
  const UserSession({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    this.organisationId,
    this.organisationName,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    final first = (json['first_name'] as String?)?.trim() ?? '';
    final last = (json['last_name'] as String?)?.trim() ?? '';
    final fullName = '$first $last'.trim();
    return UserSession(
      userId: json['user_id'] is int ? json['user_id'] as int : int.tryParse('${json['user_id']}') ?? 0,
      name: fullName.isNotEmpty ? fullName : (json['user_name'] as String? ?? ''),
      email: json['user_email'] as String? ?? '',
      role: (json['user_role'] as String? ?? '').toUpperCase(),
      organisationId: json['organisation'] is int ? json['organisation'] as int : null,
      organisationName: json['organisation_name'] as String?,
    );
  }

  final int userId;
  final String name;
  final String email;
  final String role;
  final int? organisationId;
  final String? organisationName;

  bool get isFieldOfficer => AppConfig.fieldRoles.contains(role);
  bool get isManager => role == 'MANAGER';

  bool get canRegisterFarmers => role == 'AGENT' || isManager;
  bool get canQuote => role == 'AGENT' || isManager;
  bool get canReportClaims => role == 'AGENT' || role == 'ASSESSOR' || isManager;
  bool get canInspect => role == 'ASSESSOR' || isManager;

  String get roleLabel => switch (role) {
        'AGENT' => 'Agent',
        'ASSESSOR' => 'Assessor',
        'MANAGER' => 'Manager',
        _ => role,
      };
}

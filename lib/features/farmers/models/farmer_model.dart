class Farmer {
  final int? id;
  final int? serverId;
  final int? organisationId;
  final String? organisationName; // NEW: For display purposes
  final String firstName;
  final String lastName;
  final String idNumber;
  final String phoneNumber;
  final String? email;
  final String? gender;
  final double? registration_latitude;
  final double? registration_longitude;
  final String? photoPath;
  final String syncStatus;
  final int? createdAt;
  final int? updatedAt;

  Farmer({
    this.id,
    this.serverId,
    this.organisationId,
    this.organisationName,
    required this.firstName,
    required this.lastName,
    required this.idNumber,
    required this.phoneNumber,
    this.email,
    this.gender,
    this.registration_latitude,
    this.registration_longitude,
    this.photoPath,
    this.syncStatus = 'pending',
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'organisation_id': organisationId,
      'first_name': firstName,
      'last_name': lastName,
      'id_number': idNumber,
      'phone_number': phoneNumber,
      'email': email,
      'gender': gender,
      'registration_latitude': registration_latitude,
      'registration_longitude': registration_longitude,
      'photo_path': photoPath,
      'sync_status': syncStatus,
      'created_at': createdAt ?? DateTime.now().millisecondsSinceEpoch,
      'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> toApiJson() {
    return {
      'organisation': organisationId,
      'first_name': firstName,
      'last_name': lastName,
      'id_number': idNumber,
      'phone_number': phoneNumber,
      'email': email,
      'gender': gender,
      'status': 'ACTIVE',
    };
  }

  factory Farmer.fromMap(Map<String, dynamic> map) {
    return Farmer(
      id: map['id'],
      serverId: map['server_id'],
      organisationId: map['organisation_id'],
      organisationName: map['organisation_name'], // From JOIN query
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      idNumber: map['id_number'] ?? '',
      phoneNumber: map['phone_number'] ?? '',
      email: map['email'],
      gender: map['gender'],
      registration_latitude: map['registration_latitude'],
      registration_longitude: map['registration_longitude'],
      photoPath: map['photo_path'],
      syncStatus: map['sync_status'] ?? 'pending',
      createdAt: map['created_at'],
      updatedAt: map['updated_at'],
    );
  }

  Farmer copyWith({
    int? id,
    int? serverId,
    String? syncStatus,
  }) {
    return Farmer(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      organisationId: organisationId,
      organisationName: organisationName,
      firstName: firstName,
      lastName: lastName,
      idNumber: idNumber,
      phoneNumber: phoneNumber,
      email: email,
      gender: gender,
      registration_latitude: registration_latitude,
      registration_longitude: registration_longitude,
      photoPath: photoPath,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
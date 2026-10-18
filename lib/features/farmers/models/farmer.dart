import 'dart:convert';

import '../../../core/db/syncable.dart';
import '../../../core/sync/entity_mappers.dart';

class NextOfKin {
  const NextOfKin({required this.name, required this.relationship, required this.phoneNumber});

  factory NextOfKin.fromJson(Map<String, dynamic> j) => NextOfKin(
        name: '${j['name'] ?? ''}',
        relationship: '${j['relationship'] ?? ''}',
        phoneNumber: '${j['phone_number'] ?? ''}',
      );

  final String name;
  final String relationship;
  final String phoneNumber;

  Map<String, dynamic> toJson() =>
      {'name': name, 'relationship': relationship, 'phone_number': phoneNumber};
}

class BankAccount {
  const BankAccount({required this.bankName, required this.accountNumber, required this.accountName});

  factory BankAccount.fromJson(Map<String, dynamic> j) => BankAccount(
        bankName: '${j['bank_name'] ?? ''}',
        accountNumber: '${j['account_number'] ?? ''}',
        accountName: '${j['account_name'] ?? ''}',
      );

  final String bankName;
  final String accountNumber;
  final String accountName;

  Map<String, dynamic> toJson() =>
      {'bank_name': bankName, 'account_number': accountNumber, 'account_name': accountName};
}

class Farmer {
  const Farmer({
    this.uuid,
    this.sync = const SyncInfo(status: 'pending'),
    required this.firstName,
    required this.lastName,
    required this.idNumber,
    required this.phoneNumber,
    this.email,
    this.gender,
    this.dateOfBirth,
    this.category,
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    this.photoUrl,
    this.nextOfKin = const [],
    this.bankAccounts = const [],
    this.notice,
    this.createdAt,
    this.farmCount = 0,
    this.localPhotoPath,
  });

  factory Farmer.fromRow(Map<String, Object?> r) => Farmer(
        uuid: r['client_uuid'] as String,
        sync: SyncInfo.fromRow(r),
        firstName: r['first_name'] as String? ?? '',
        lastName: r['last_name'] as String? ?? '',
        idNumber: r['id_number'] as String? ?? '',
        phoneNumber: r['phone_number'] as String? ?? '',
        email: r['email'] as String?,
        gender: r['gender'] as String?,
        dateOfBirth: r['date_of_birth'] as String?,
        category: r['farmer_category'] as String?,
        latitude: (r['registration_latitude'] as num?)?.toDouble(),
        longitude: (r['registration_longitude'] as num?)?.toDouble(),
        gpsAccuracy: (r['registration_accuracy'] as num?)?.toDouble(),
        photoUrl: r['photo_url'] as String?,
        nextOfKin: decodeList(r['next_of_kin']).map(NextOfKin.fromJson).toList(),
        bankAccounts: decodeList(r['bank_accounts']).map(BankAccount.fromJson).toList(),
        notice: r['notice'] as String?,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        farmCount: (r['farm_count'] as int?) ?? 0,
        localPhotoPath: r['local_photo'] as String?,
      );

  final String? uuid;
  final SyncInfo sync;
  final String firstName;
  final String lastName;
  final String idNumber;
  final String phoneNumber;
  final String? email;
  final String? gender;
  final String? dateOfBirth;
  final String? category;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;
  final String? photoUrl;
  final List<NextOfKin> nextOfKin;
  final List<BankAccount> bankAccounts;
  final String? notice;
  final DateTime? createdAt;
  final int farmCount;
  final String? localPhotoPath;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final a = firstName.isNotEmpty ? firstName[0] : '';
    final b = lastName.isNotEmpty ? lastName[0] : '';
    return (a + b).toUpperCase();
  }

  String get genderLabel => switch (gender?.toUpperCase()) {
        'M' || 'MALE' => 'Male',
        'F' || 'FEMALE' => 'Female',
        'O' || 'OTHER' => 'Other',
        null || '' => '-',
        _ => gender!,
      };

  Map<String, Object?> toColumns() => {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'id_number': idNumber.trim(),
        'phone_number': phoneNumber.trim(),
        'email': (email?.trim().isEmpty ?? true) ? null : email!.trim(),
        'gender': gender,
        'date_of_birth': dateOfBirth,
        'farmer_category': (category?.trim().isEmpty ?? true) ? null : category!.trim(),
        'registration_latitude': latitude,
        'registration_longitude': longitude,
        'registration_accuracy': gpsAccuracy,
        'next_of_kin': jsonEncode(nextOfKin.map((e) => e.toJson()).toList()),
        'bank_accounts': jsonEncode(bankAccounts.map((e) => e.toJson()).toList()),
      };
}

// End-to-end check of the sync engine against a running backend.
//
// Skipped unless LIVE_API_BASE_URL is set, e.g.:
//   LIVE_API_BASE_URL=http://localhost:8001/api/v1 flutter test test/integration
//
// Expects the local seed: agent@cropinsurance.test / customer@cropinsurance.test
// (password in LIVE_API_PASSWORD, default Local@Test1), an ACTIVE product,
// an office farmer with a WRITTEN policy, and a farmer with ID 99000002.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:insurance_mobile/core/auth/auth_controller.dart';
import 'package:insurance_mobile/core/auth/token_store.dart';
import 'package:insurance_mobile/core/db/app_database.dart';
import 'package:insurance_mobile/core/db/meta_store.dart';
import 'package:insurance_mobile/core/db/syncable.dart';
import 'package:insurance_mobile/core/media/media_repository.dart';
import 'package:insurance_mobile/core/network/api_client.dart';
import 'package:insurance_mobile/core/network/api_exceptions.dart';
import 'package:insurance_mobile/core/sync/sync_engine.dart';
import 'package:insurance_mobile/core/sync/sync_transport.dart';
import 'package:insurance_mobile/features/claims/data/claim_repository.dart';
import 'package:insurance_mobile/features/claims/models/claim.dart';
import 'package:insurance_mobile/features/farmers/data/farmer_repository.dart';
import 'package:insurance_mobile/features/farmers/models/farmer.dart';
import 'package:insurance_mobile/features/farms/data/farm_repository.dart';
import 'package:insurance_mobile/features/farms/models/farm.dart';
import 'package:insurance_mobile/features/inspections/data/inspection_repository.dart';
import 'package:insurance_mobile/features/inspections/models/inspection.dart';
import 'package:insurance_mobile/features/quotations/data/quotation_repository.dart';

import '../support/fakes.dart';

const _jpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAEAAQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDiqKKK+aPjz//Z';

void main() {
  final baseUrl = Platform.environment['LIVE_API_BASE_URL'];
  final password = Platform.environment['LIVE_API_PASSWORD'] ?? 'Local@Test1';

  test('field visit captured offline syncs end to end', () async {
    final db = await openTestDb();
    final changes = DataChanges();
    final tokens = MemoryTokenStore();
    final api = ApiClient(tokens: tokens, baseUrl: baseUrl!);
    final auth = AuthController(api: api, tokens: tokens, db: db);
    final engine = SyncEngine(db: db, transport: ApiSyncTransport(api));
    final farmers = FarmerRepository(db, changes);
    final farms = FarmRepository(db, changes);
    final quotations = QuotationRepository(db, changes);
    final claims = ClaimRepository(db, changes);
    final inspections = InspectionRepository(db, changes);
    final media = MediaRepository(db, changes);

    // Non field roles are refused.
    await expectLater(auth.login('customer@cropinsurance.test', password), throwsA(isA<LoginRefused>()));

    await auth.login('agent@cropinsurance.test', password);
    expect(auth.session!.role, 'AGENT');

    // 1. Full download after login.
    var report = await engine.sync(fullDownload: true);
    expect(report.ok, isTrue, reason: '${report.error}');
    final products = await quotations.activeProducts();
    final product = products.firstWhere((p) => p.name == 'IT Maize Cover');
    final policy = (await quotations.list(claimableOnly: true)).firstWhere((q) => q.policyNumber == 'POL-IT-1');
    final office = (await farmers.list(query: 'Office Farmer')).first;
    expect(office.sync.canEditFromDevice, isFalse, reason: 'office record without device uuid');

    // 2. Capture a field visit offline.
    final idNumber = '${30000000 + Random().nextInt(9999999)}';
    final farmerUuid = await farmers.create(Farmer(
      firstName: 'Jane', lastName: 'Wanjiku', idNumber: idNumber, phoneNumber: '0712345678', gender: 'F',
      dateOfBirth: '1990-05-01', latitude: -1.286389, longitude: 36.817223,
      nextOfKin: const [NextOfKin(name: 'John', relationship: 'Spouse', phoneNumber: '0700000000')],
      bankAccounts: const [BankAccount(bankName: 'KCB', accountNumber: '123', accountName: 'Jane W')],
    ));
    final dupUuid = await farmers.create(const Farmer(
        firstName: 'Already', lastName: 'Registered', idNumber: '99000002', phoneNumber: '0711000002'));
    final badUuid = await farmers.create(Farmer(
        firstName: 'Bad', lastName: 'Email', idNumber: '${idNumber}1', phoneNumber: '0712345679', email: 'not-an-email'));
    final farmUuid = await farms.create(Farm(
        farmerUuid: farmerUuid, name: 'Shamba', size: 2.5, unit: 'ACRES', county: 'Nakuru',
        subCounty: 'Njoro', ward: 'Mau Narok', latitude: -1.2, longitude: 36.8));
    final quoteUuid = await quotations.create(farmUuid: farmUuid, product: product, sumInsured: 50000);
    final claimUuid = await claims.create(Claim(
        quotationUuid: policy.uuid, estimatedLoss: 20000, cause: 'Drought',
        description: 'Long dry spell destroyed the crop', dateOfLoss: '2026-10-01', latitude: -1.2, longitude: 36.8));
    final inspectionUuid = await inspections.create(Inspection(
        farmUuid: farmUuid, type: 'MID_SEASON', status: 'IN_PROGRESS', scheduledDate: '2026-10-14',
        scheduledTime: '09:30', checkInLat: -1.2, checkInLon: 36.8, checkInTime: DateTime.now(),
        findings: const {'crop_condition': 'Fair', 'damage_percent': 20, 'notes': 'Some wilting'}));

    final photo = File('${(await Directory.systemTemp.createTemp('it')).path}/p.jpg')
      ..writeAsBytesSync(base64Decode(_jpeg));
    await media.add('claim', claimUuid, CapturedPhoto(path: photo.path, latitude: -1.2, longitude: 36.8));
    await media.setProfilePhoto(farmerUuid, CapturedPhoto(path: photo.path));
    await media.add('inspection', inspectionUuid, CapturedPhoto(path: photo.path));

    // 3. Sync.
    report = await engine.sync();
    expect(report.ok, isTrue, reason: '${report.error}');
    expect(report.duplicates, 1);
    expect(report.rejected, 1);

    final farmer = (await farmers.get(farmerUuid))!;
    expect(farmer.sync.isSynced, isTrue, reason: farmer.sync.error);
    expect(farmer.nextOfKin.single.name, 'John');
    expect((await farmers.get(dupUuid))!.notice, contains('Already registered'));
    final bad = (await farmers.get(badUuid))!;
    expect(bad.sync.needsAttention, isTrue);
    expect(bad.sync.error, contains('Email'));

    expect((await farms.get(farmUuid))!.sync.isSynced, isTrue);
    final quote = (await quotations.get(quoteUuid))!;
    expect(quote.sync.isSynced, isTrue, reason: quote.sync.error);
    expect(quote.premiumAmount, 2500);
    expect(quote.status, 'OPEN');
    final claim = (await claims.get(claimUuid))!;
    expect(claim.sync.isSynced, isTrue, reason: claim.sync.error);
    expect(claim.claimNumber, startsWith('CLM-'));
    expect(claim.status, 'OPEN');
    final inspection = (await inspections.get(inspectionUuid))!;
    expect(inspection.sync.isSynced, isTrue, reason: inspection.sync.error);
    expect(inspection.cropCondition, 'Fair');

    expect(report.photosUploaded, 3, reason: 'photo error: ${report.photoError}');
    expect((await farmers.get(farmerUuid))!.photoUrl, isNotNull);

    // 4. Edit after sync re-queues and updates the same server record.
    await farmers.update(farmerUuid, Farmer(
        firstName: 'Jane', lastName: 'Wanjiku-Otieno', idNumber: idNumber, phoneNumber: '0712345678', gender: 'F'));
    final serverId = farmer.sync.serverId;
    report = await engine.sync();
    final edited = (await farmers.get(farmerUuid))!;
    expect(edited.sync.isSynced, isTrue);
    expect(edited.sync.serverId, serverId);
    expect(edited.lastName, 'Wanjiku-Otieno');
    expect(await MetaStore.get(db, MetaKeys.lastSync), isNotNull);

    // 5. Expired access token is refreshed transparently.
    tokens.access = 'expired-token';
    report = await engine.sync();
    expect(report.ok, isTrue, reason: '${report.error}');
    expect(tokens.access, isNot('expired-token'));

    // 6. Rejected refresh token -> sign in again; nothing local is lost.
    tokens.access = 'expired-token';
    tokens.refresh = 'bad-refresh';
    final before = (await db.query(Tables.farmers)).length;
    report = await engine.sync();
    expect(report.error, isA<AuthRequiredException>());
    expect((await db.query(Tables.farmers)).length, before);

    await db.close();
  }, skip: baseUrl == null ? 'Set LIVE_API_BASE_URL to run against a server' : false, timeout: const Timeout(Duration(minutes: 3)));
}

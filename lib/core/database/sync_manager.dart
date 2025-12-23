import 'package:sqflite/sqflite.dart';
import '../network/api_client.dart';
import 'app_database.dart';
import '../../features/farmers/models/farmer_model.dart';

class SyncManager {
  final ApiClient _apiClient = ApiClient.instance;
  final Database db;

  SyncManager(this.db);

  Future<SyncResult> syncAll() async {
    if (!await _apiClient.isOnline()) {
      print('📵 No internet connection. Skipping sync.');
      return SyncResult(
        success: false,
        message: 'No internet connection',
        farmersSynced: 0,
        claimsSynced: 0,
      );
    }

    print('🔄 Starting sync...');

    int farmersSynced = 0;
    int claimsSynced = 0;

    try {
      farmersSynced = await _syncFarmers();
      claimsSynced = await _syncClaims();
      await _syncMedia();

      print('✅ Sync complete! Farmers: $farmersSynced, Claims: $claimsSynced');

      return SyncResult(
        success: true,
        message: 'Sync completed successfully',
        farmersSynced: farmersSynced,
        claimsSynced: claimsSynced,
      );
    } catch (e) {
      print('❌ Sync failed: $e');
      return SyncResult(
        success: false,
        message: 'Sync failed: $e',
        farmersSynced: farmersSynced,
        claimsSynced: claimsSynced,
      );
    }
  }

  Future<int> _syncFarmers() async {
    final pendingFarmers = await db.query(
      'farmers',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );

    int synced = 0;

    for (var farmerMap in pendingFarmers) {
      try {
        final farmer = Farmer.fromMap(farmerMap);
        final response = await _apiClient.createFarmer(farmer.toApiJson());

        // Update local record with server ID
        await db.update(
          'farmers',
          {
            'server_id': response['farmer_id'],
            'sync_status': 'synced',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [farmer.id],
        );

        synced++;
        print('✅ Synced farmer: ${farmer.firstName} ${farmer.lastName}');
      } catch (e) {
        print('❌ Failed to sync farmer ${farmerMap['id']}: $e');
        await db.update(
          'farmers',
          {'sync_status': 'error'},
          where: 'id = ?',
          whereArgs: [farmerMap['id']],
        );
      }
    }

    return synced;
  }

  Future<int> _syncClaims() async {
    final pendingClaims = await db.query(
      'claims',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );

    int synced = 0;

    for (var claimMap in pendingClaims) {
      try {
        // Get farmer's server_id
        final farmer = await db.query(
          'farmers',
          where: 'id = ?',
          whereArgs: [claimMap['farmer_id']],
        );

        if (farmer.isEmpty || farmer.first['server_id'] == null) {
          print('⚠️ Skipping claim - farmer not synced yet');
          continue;
        }

        final claimData = {
          'farmer': farmer.first['server_id'],
          'quotation': claimMap['quotation_id'],
          'estimated_loss_amount': claimMap['estimated_loss_amount'],
          'loss_details': claimMap['loss_details'],
          'status': 'OPEN',
        };

        final response = await _apiClient.createClaim(claimData);

        await db.update(
          'claims',
          {
            'server_id': response['claim_id'],
            'claim_number': response['claim_number'],
            'sync_status': 'synced',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [claimMap['id']],
        );

        synced++;
        print('✅ Synced claim: ${response['claim_number']}');
      } catch (e) {
        print('❌ Failed to sync claim ${claimMap['id']}: $e');
      }
    }

    return synced;
  }

  Future<void> _syncMedia() async {
    final pendingMedia = await db.query(
      'media_queue',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );

    for (var media in pendingMedia) {
      try {
        final url = await _apiClient.uploadImage(
          media['file_path'] as String,
          'photo',
        );

        await db.update(
          'media_queue',
          {'sync_status': 'synced'},
          where: 'id = ?',
          whereArgs: [media['id']],
        );

        print('✅ Uploaded media: $url');
      } catch (e) {
        print('❌ Failed to upload media ${media['id']}: $e');
      }
    }
  }
}

class SyncResult {
  final bool success;
  final String message;
  final int farmersSynced;
  final int claimsSynced;

  SyncResult({
    required this.success,
    required this.message,
    required this.farmersSynced,
    required this.claimsSynced,
  });
}
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';

import 'claim_detail_screen.dart';
import 'enhanced_new_claim_screen.dart';
import '../models/claims_model.dart'; // ADDED: Import Claim model

class ClaimsListScreen extends StatefulWidget {
  const ClaimsListScreen({Key? key}) : super(key: key);

  @override
  State<ClaimsListScreen> createState() => _ClaimsListScreenState();
}

class _ClaimsListScreenState extends State<ClaimsListScreen> {
  List<Map<String, dynamic>> _claims = [];
  bool _isLoading = true;
  String _filter = 'all'; // all, pending, synced

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    setState(() => _isLoading = true);

    try {
      final db = await AppDatabase.instance.database;

      String whereClause = '';
      List<dynamic> whereArgs = [];

      if (_filter == 'pending') {
        whereClause = 'sync_status = ?';
        whereArgs = ['pending'];
      } else if (_filter == 'synced') {
        whereClause = 'sync_status = ?';
        whereArgs = ['synced'];
      }

      final claims = whereClause.isEmpty
          ? await db.query('claims', orderBy: 'created_at DESC')
          : await db.query(
        'claims',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
      );

      // Get farmer names for each claim
      for (var claim in claims) {
        final farmers = await db.query(
          'farmers',
          where: 'id = ?',
          whereArgs: [claim['farmer_id']],
        );
        if (farmers.isNotEmpty) {
          claim['farmer_name'] =
          '${farmers.first['first_name']} ${farmers.first['last_name']}';
        }
      }

      setState(() {
        _claims = claims;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load claims: $e');
    }
  }

  Future<void> _syncClaims() async {
    if (!await ApiClient.instance.isOnline()) {
      _showError('No internet connection');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Syncing claims...')),
    );

    try {
      final db = await AppDatabase.instance.database;
      final pendingClaims = await db.query(
        'claims',
        where: 'sync_status = ?',
        whereArgs: ['pending'],
      );

      int synced = 0;
      for (var claim in pendingClaims) {
        try {
          // Get farmer's server_id
          final farmers = await db.query(
            'farmers',
            where: 'id = ?',
            whereArgs: [claim['farmer_id']],
          );

          if (farmers.isEmpty || farmers.first['server_id'] == null) {
            continue;
          }

          final claimData = {
            'farmer': farmers.first['server_id'],
            'quotation': claim['quotation_id'],
            'estimated_loss_amount': claim['estimated_loss_amount'],
            'loss_details': claim['loss_details'],
            'status': 'OPEN',
          };

          final response = await ApiClient.instance.createClaim(claimData);

          await db.update(
            'claims',
            {
              'server_id': response['claim_id'],
              'claim_number': response['claim_number'],
              'sync_status': 'synced',
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [claim['id']],
          );

          synced++;
        } catch (e) {
          print('Failed to sync claim ${claim['id']}: $e');
        }
      }

      await _loadClaims();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced $synced claims')),
        );
      }
    } catch (e) {
      _showError('Sync failed: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'synced':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'synced':
        return Icons.cloud_done;
      case 'pending':
        return Icons.cloud_upload;
      case 'error':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Claims Assessment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncClaims,
            tooltip: 'Sync Claims',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _filter = value);
              _loadClaims();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Claims')),
              const PopupMenuItem(value: 'pending', child: Text('Pending Sync')),
              const PopupMenuItem(value: 'synced', child: Text('Synced')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _claims.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No claims found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create a new claim',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadClaims,
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: _claims.length,
          itemBuilder: (context, index) {
            final claim = _claims[index];
            final syncStatus = claim['sync_status'] ?? 'pending';

            return Card(
              margin: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getStatusColor(syncStatus),
                  child: Icon(
                    _getStatusIcon(syncStatus),
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  claim['farmer_name'] ?? 'Unknown Farmer',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Amount: KES ${claim['estimated_loss_amount']}',
                    ),
                    if (claim['claim_number'] != null)
                      Text(
                        'Claim #: ${claim['claim_number']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    Text(
                      'Status: $syncStatus',
                      style: TextStyle(
                        color: _getStatusColor(syncStatus),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // FIXED: Convert Map to Claim object and use ClaimDetailsScreen
                  final claimObj = Claim.fromMap(claim);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ClaimDetailsScreen(
                        claim: claimObj,
                      ),
                    ),
                  ).then((_) => _loadClaims());
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EnhancedNewClaimScreen(),
            ),
          ).then((_) => _loadClaims());
        },
        icon: const Icon(Icons.add),
        label: const Text('New Claim'),
      ),
    );
  }
}
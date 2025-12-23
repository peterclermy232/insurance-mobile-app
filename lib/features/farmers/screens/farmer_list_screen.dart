import 'package:flutter/material.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/sync_manager.dart';
import '../../../core/network/api_client.dart';
import '../models/farmer_model.dart';
import 'farmer_form_screen.dart';

class FarmerListScreen extends StatefulWidget {
  const FarmerListScreen({Key? key}) : super(key: key);

  @override
  State<FarmerListScreen> createState() => _FarmerListScreenState();
}

class _FarmerListScreenState extends State<FarmerListScreen> {
  List<Farmer> _farmers = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFarmers();
  }

  Future<void> _loadFarmers() async {
    setState(() => _isLoading = true);

    try {
      final db = await AppDatabase.instance.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'farmers',
        orderBy: 'created_at DESC',
      );

      setState(() {
        _farmers = maps.map((map) => Farmer.fromMap(map)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading farmers: $e')),
        );
      }
    }
  }

  Future<void> _syncData() async {
    setState(() => _isSyncing = true);

    try {
      final db = await AppDatabase.instance.database;
      final syncManager = SyncManager(db);
      final result = await syncManager.syncAll();

      await _loadFarmers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success
                ? '✅ Synced ${result.farmersSynced} farmers'
                : '❌ ${result.message}'),
            backgroundColor: result.success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  List<Farmer> get _filteredFarmers {
    if (_searchQuery.isEmpty) return _farmers;

    return _farmers.where((farmer) {
      final query = _searchQuery.toLowerCase();
      return farmer.firstName.toLowerCase().contains(query) ||
          farmer.lastName.toLowerCase().contains(query) ||
          farmer.idNumber.toLowerCase().contains(query) ||
          farmer.phoneNumber.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registered Farmers'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : _syncData,
            tooltip: 'Sync with server',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFarmers,
            tooltip: 'Refresh',
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Logout'),
                onTap: () async {
                  await ApiClient.instance.logout();
                  if (mounted) {
                    Navigator.of(context).pushReplacementNamed('/');
                  }
                },
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search farmers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('Total', _farmers.length.toString(), Icons.people),
                    _buildStat(
                      'Pending',
                      _farmers.where((f) => f.syncStatus == 'pending').length.toString(),
                      Icons.cloud_upload,
                    ),
                    _buildStat(
                      'Synced',
                      _farmers.where((f) => f.syncStatus == 'synced').length.toString(),
                      Icons.cloud_done,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredFarmers.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No farmers found',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FarmerFormScreen(),
                        ),
                      );
                      if (result == true) _loadFarmers();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Farmer'),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredFarmers.length,
              itemBuilder: (context, index) {
                final farmer = _filteredFarmers[index];
                return _buildFarmerCard(farmer);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FarmerFormScreen(),
            ),
          );
          if (result == true) _loadFarmers();
        },
        backgroundColor: Colors.green,
        icon: const Icon(Icons.add),
        label: const Text('Add Farmer'),
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.green),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildFarmerCard(Farmer farmer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green,
          child: Text(
            farmer.firstName[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          '${farmer.firstName} ${farmer.lastName}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${farmer.idNumber}'),
            Text('Phone: ${farmer.phoneNumber}'),
          ],
        ),
        trailing: _buildSyncStatusIcon(farmer.syncStatus),
      ),
    );
  }

  Widget _buildSyncStatusIcon(String status) {
    switch (status) {
      case 'synced':
        return const Icon(Icons.cloud_done, color: Colors.green);
      case 'pending':
        return const Icon(Icons.cloud_upload, color: Colors.orange);
      case 'error':
        return const Icon(Icons.error, color: Colors.red);
      default:
        return const Icon(Icons.cloud_off, color: Colors.grey);
    }
  }
}
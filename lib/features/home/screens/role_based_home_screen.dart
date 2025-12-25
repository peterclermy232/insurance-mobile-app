// lib/features/home/screens/role_based_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../claims/screens/enhanced_new_claim_screen.dart';
import '../../claims/screens/claims_list_screen.dart';
import '../../farmers/screens/farmer_list_screen.dart';
import '../../farmers/screens/farmer_form_screen.dart';
import '../../auth/screens/enhanced_login_screen.dart';
import '../../../core/network/api_client.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/sync_manager.dart';

class RoleBasedHomeScreen extends StatefulWidget {
  const RoleBasedHomeScreen({Key? key}) : super(key: key);

  @override
  State<RoleBasedHomeScreen> createState() => _RoleBasedHomeScreenState();
}

class _RoleBasedHomeScreenState extends State<RoleBasedHomeScreen> {
  final _storage = const FlutterSecureStorage();

  String _userName = '';
  String _userRole = '';
  int _currentIndex = 0;
  bool _isSyncing = false;

  Map<String, dynamic> _stats = {
    'farmers': 0,
    'claims': 0,
    'pending_sync': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadStats();
  }

  Future<void> _loadUserInfo() async {
    final name = await _storage.read(key: 'user_name') ?? 'User';
    final role = await _storage.read(key: 'user_role') ?? 'USER';

    setState(() {
      _userName = name;
      _userRole = role;
    });
  }

  Future<void> _loadStats() async {
    try {
      final db = await AppDatabase.instance.database;

      final farmersCount = await db.rawQuery('SELECT COUNT(*) as count FROM farmers');
      final claimsCount = await db.rawQuery('SELECT COUNT(*) as count FROM claims');
      final pendingCount = await db.rawQuery(
          "SELECT COUNT(*) as count FROM farmers WHERE sync_status = 'pending' "
              "UNION ALL SELECT COUNT(*) FROM claims WHERE sync_status = 'pending'"
      );

      setState(() {
        _stats['farmers'] = (farmersCount.first['count'] as int?) ?? 0;
        _stats['claims'] = (claimsCount.first['count'] as int?) ?? 0;
        _stats['pending_sync'] = pendingCount.fold<int>(
            0, (sum, row) => sum + ((row['count'] as int?) ?? 0)
        );
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  Future<void> _syncData() async {
    setState(() => _isSyncing = true);

    try {
      final db = await AppDatabase.instance.database;
      final syncManager = SyncManager(db);
      final result = await syncManager.syncAll();

      await _loadStats();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success
                ? '✅ Sync complete! ${result.farmersSynced} farmers, ${result.claimsSynced} claims'
                : '❌ ${result.message}'),
            backgroundColor: result.success ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
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

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('LOGOUT'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ApiClient.instance.logout();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EnhancedLoginScreen()),
            (route) => false,
      );
    }
  }

  // Role-based permissions
  bool get _canRegisterFarmers => ['ADMIN', 'MANAGER', 'SUPERUSER'].contains(_userRole);
  bool get _canViewFarmers => true; // Everyone can view
  bool get _canCreateClaims => true; // Everyone can create claims
  bool get _canViewAllClaims => ['ADMIN', 'MANAGER', 'ASSESSOR', 'SUPERUSER'].contains(_userRole);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Insurance Mobile'),
            Text(
              _userName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        actions: [
          if (_stats['pending_sync']! > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload, size: 16),
                  const SizedBox(width: 4),
                  Text('${_stats['pending_sync']}'),
                ],
              ),
            ),
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
            tooltip: 'Sync Data',
          ),
          PopupMenuButton<String>(
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                enabled: false,
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(_userName),
                  subtitle: Text(_userRole),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'about',
                child: const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: const ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Logout', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (String value) {
              if (value == 'about') {
                _showAboutDialog();
              } else if (value == 'logout') {
                _logout();
              }
            },
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          if (_canViewFarmers)
            const BottomNavigationBarItem(
              icon: Icon(Icons.people),
              label: 'Farmers',
            ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Claims',
          ),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildBody() {
    // Adjust index based on available tabs
    final List<Widget> screens = [
      _buildDashboard(),
      if (_canViewFarmers) const FarmerListScreen(),
      const ClaimsListScreen(),
    ];

    // Ensure currentIndex is valid
    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    return screens[_currentIndex];
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome Card
          Card(
            elevation: 4,
            color: Colors.green[50],
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.green,
                        radius: 30,
                        child: Text(
                          _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome, $_userName!',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _userRole,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Farmers',
                  _stats['farmers'].toString(),
                  Icons.people,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Claims',
                  _stats['claims'].toString(),
                  Icons.assignment,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            'Pending Sync',
            _stats['pending_sync'].toString(),
            Icons.cloud_upload,
            _stats['pending_sync']! > 0 ? Colors.red : Colors.green,
          ),
          const SizedBox(height: 24),

          // Quick Actions
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (_canCreateClaims)
            _buildActionButton(
              'New Claim Assessment',
              'Create a new insurance claim',
              Icons.add_circle,
              Colors.green,
                  () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EnhancedNewClaimScreen(),
                ),
              ).then((_) => _loadStats()),
            ),
          const SizedBox(height: 12),

          if (_canRegisterFarmers)
            _buildActionButton(
              'Register Farmer',
              'Add a new farmer to the system',
              Icons.person_add,
              Colors.blue,
                  () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FarmerFormScreen(),
                ),
              ).then((_) => _loadStats()),
            ),
          const SizedBox(height: 12),

          _buildActionButton(
            'Sync Data',
            'Upload and download data',
            Icons.sync,
            Colors.orange,
            _syncData,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      String title,
      String subtitle,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: color),
        onTap: onTap,
      ),
    );
  }

  Widget? _buildFAB() {
    if (_currentIndex == 0) {
      // Dashboard - Create Claim FAB
      if (_canCreateClaims) {
        return FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const EnhancedNewClaimScreen(),
            ),
          ).then((_) => _loadStats()),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.add),
          label: const Text('New Claim'),
        );
      }
    } else if (_currentIndex == 1 && _canRegisterFarmers) {
      // Farmers - Register Farmer FAB
      return FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const FarmerFormScreen(),
          ),
        ).then((_) => _loadStats()),
        backgroundColor: Colors.green,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Farmer'),
      );
    }
    return null;
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Insurance Mobile',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.agriculture, size: 48, color: Colors.green),
      children: [
        const Text('Field data collection app for agricultural insurance.'),
        const SizedBox(height: 8),
        Text('Logged in as: $_userName ($_userRole)'),
      ],
    );
  }
}
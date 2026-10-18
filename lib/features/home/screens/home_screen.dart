import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/syncable.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../../claims/screens/claim_form_screen.dart';
import '../../claims/screens/claim_list_screen.dart';
import '../../farmers/screens/farmer_form_screen.dart';
import '../../farmers/screens/farmer_list_screen.dart';
import '../../farms/screens/farm_list_screen.dart';
import '../../inspections/screens/inspection_form_screen.dart';
import '../../inspections/screens/inspection_list_screen.dart';
import '../../quotations/screens/quotation_form_screen.dart';
import '../../quotations/screens/quotation_list_screen.dart';
import '../../sync/screens/sync_center_screen.dart';
import '../../sync/widgets/sync_actions.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthController>();
      final online = context.read<ConnectivityService>().isOnline;
      // Catch up quietly on app start when there's a connection.
      if (online && !auth.needsReauth) context.read<SyncController>().syncNow(trigger: 'startup');
    });
  }

  Future<Map<String, int>> _counts(Database db) async {
    final out = <String, int>{};
    for (final table in Tables.entities) {
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      out[table] = (r.first['c'] as int?) ?? 0;
    }
    return out;
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _signOut() async {
    final auth = context.read<AuthController>();
    final unsynced = await auth.unsyncedCount();
    if (!mounted) return;
    if (unsynced == 0) {
      final ok = await confirm(context,
          title: 'Sign out?', message: 'You will need an internet connection to sign in again.', confirmLabel: 'Sign out');
      if (ok) await auth.logout();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsynced records'),
        content: Text('$unsynced record${unsynced == 1 ? ' has' : 's have'} not been uploaded yet. '
            'They will stay on this device and upload the next time you sign in and sync. '
            'Signing in again needs an internet connection.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'signout'), child: const Text('Sign out anyway')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'sync'), child: const Text('Sync first')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'sync') {
      await syncWithFeedback(context);
    } else if (choice == 'signout') {
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthController>().session;
    final sync = context.watch<SyncController>();
    final db = context.read<Database>();
    final changes = context.read<DataChanges>();
    if (session == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final actions = <(IconData, String, Widget)>[
      if (session.canRegisterFarmers) (Icons.person_add_alt_1, 'Register farmer', const FarmerFormScreen()),
      if (session.canQuote) (Icons.request_quote_outlined, 'New quotation', const QuotationFormScreen()),
      if (session.canReportClaims) (Icons.report_outlined, 'Report claim', const ClaimFormScreen()),
      if (session.canInspect) (Icons.fact_check_outlined, 'New inspection', const InspectionFormScreen()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            onPressed: sync.isSyncing ? null : () => syncWithFeedback(context),
            icon: sync.isSyncing
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'sync') _open(const SyncCenterScreen());
              if (v == 'about') {
                showAboutDialog(
                  context: context,
                  applicationName: AppConfig.appName,
                  applicationVersion: '1.0.0',
                  children: [const Text('Server: ${AppConfig.apiBaseUrl}')],
                );
              }
              if (v == 'signout') _signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'sync', child: Text('Sync details')),
              PopupMenuItem(value: 'about', child: Text('About')),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        const StatusBanners(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => syncWithFeedback(context),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Hello, ${session.name.split(' ').first}',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text([session.roleLabel, if (session.organisationName != null) session.organisationName].join(' - '),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                SyncStatusCard(onOpenDetails: () => _open(const SyncCenterScreen())),
                const SizedBox(height: 20),
                if (actions.isNotEmpty) ...[
                  Text('Quick actions', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.4,
                    children: [
                      for (final (icon, label, screen) in actions)
                        _ActionTile(icon: icon, label: label, onTap: () => _open(screen)),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                Text('Records on this device', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                DataBuilder<Map<String, int>>(
                  changes: changes,
                  load: () => _counts(db),
                  builder: (context, counts) => Column(children: [
                    _CountTile(Icons.people_outline, 'Farmers', counts[Tables.farmers] ?? 0,
                        () => _open(const FarmerListScreen())),
                    _CountTile(Icons.landscape_outlined, 'Farms', counts[Tables.farms] ?? 0,
                        () => _open(const FarmListScreen())),
                    _CountTile(Icons.request_quote_outlined, 'Quotations and policies', counts[Tables.quotations] ?? 0,
                        () => _open(const QuotationListScreen())),
                    _CountTile(Icons.report_outlined, 'Claims', counts[Tables.claims] ?? 0,
                        () => _open(const ClaimListScreen())),
                    _CountTile(Icons.fact_check_outlined, 'Inspections', counts[Tables.inspections] ?? 0,
                        () => _open(const InspectionListScreen())),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(icon, color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile(this.icon, this.label, this.count, this.onTap);
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(label),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$count', style: Theme.of(context).textTheme.titleMedium),
            const Icon(Icons.chevron_right),
          ]),
          onTap: onTap,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/syncable.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../../claims/screens/claim_detail_screen.dart';
import '../../farmers/screens/farmer_detail_screen.dart';
import '../../farms/screens/farm_detail_screen.dart';
import '../../inspections/screens/inspection_detail_screen.dart';
import '../../quotations/screens/quotation_detail_screen.dart';
import '../widgets/sync_actions.dart';

class _Issue {
  _Issue(this.table, this.uuid, this.title, this.status, this.error);
  final String table;
  final String uuid;
  final String title;
  final String status;
  final String? error;
}

/// Everything waiting to upload or rejected by the server.
class SyncCenterScreen extends StatelessWidget {
  const SyncCenterScreen({super.key});

  static const _labels = {
    Tables.farmers: 'Farmer',
    Tables.farms: 'Farm',
    Tables.quotations: 'Quotation',
    Tables.claims: 'Claim',
    Tables.inspections: 'Inspection',
  };

  static const _titleSql = {
    Tables.farmers: "first_name || ' ' || last_name",
    Tables.farms: 'farm_name',
    Tables.quotations: "COALESCE(policy_number, product_name, 'Quotation')",
    Tables.claims: "COALESCE(claim_number, 'New claim')",
    Tables.inspections: 'inspection_type',
  };

  Future<List<_Issue>> _load(Database db) async {
    final out = <_Issue>[];
    for (final table in Tables.entities) {
      final rows = await db.rawQuery(
        'SELECT client_uuid, ${_titleSql[table]} AS title, sync_status, sync_error FROM $table '
        'WHERE sync_status != ? ORDER BY updated_at DESC',
        [SyncStatus.synced],
      );
      for (final r in rows) {
        final raw = r['title'] as String? ?? '';
        final title = table == Tables.inspections ? Fmt.enumLabel(raw) : raw;
        out.add(_Issue(table, r['client_uuid'] as String, '${_labels[table]}: $title',
            r['sync_status'] as String, r['sync_error'] as String?));
      }
    }
    out.sort((a, b) => (b.status == SyncStatus.error ? 1 : 0) - (a.status == SyncStatus.error ? 1 : 0));
    return out;
  }

  Widget _detail(_Issue i) => switch (i.table) {
        Tables.farmers => FarmerDetailScreen(uuid: i.uuid),
        Tables.farms => FarmDetailScreen(uuid: i.uuid),
        Tables.quotations => QuotationDetailScreen(uuid: i.uuid),
        Tables.claims => ClaimDetailScreen(uuid: i.uuid),
        _ => InspectionDetailScreen(uuid: i.uuid),
      };

  @override
  Widget build(BuildContext context) {
    final db = context.read<Database>();
    final changes = context.read<DataChanges>();
    final sync = context.watch<SyncController>();
    final report = sync.lastReport;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync details')),
      body: Column(children: [
        const StatusBanners(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const SyncStatusCard(),
            const SizedBox(height: 12),
            if (report != null)
              SectionCard(title: 'Last attempt', icon: Icons.history, children: [
                Text(report.ok ? report.summary : 'Failed: ${report.summary}'),
              ]),
            const SizedBox(height: 12),
            DataBuilder<List<_Issue>>(
              changes: changes,
              load: () => _load(db),
              builder: (context, issues) => issues.isEmpty
                  ? const EmptyState(
                      icon: Icons.cloud_done_outlined,
                      title: 'Nothing waiting',
                      message: 'Every record on this device has been uploaded.',
                    )
                  : SectionCard(
                      title: 'Waiting to upload (${issues.length})',
                      icon: Icons.cloud_upload_outlined,
                      children: [
                        for (final i in issues)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(i.title),
                            subtitle: i.error == null ? null : Text(i.error!, maxLines: 3, overflow: TextOverflow.ellipsis),
                            trailing: SyncBadge(SyncInfo(status: i.status), compact: true),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _detail(i))),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            SectionCard(title: 'Advanced', icon: Icons.settings_outlined, children: [
              const Text('Download everything again from the server. Records not yet uploaded are kept.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: sync.isSyncing ? null : () => syncWithFeedback(context, fullDownload: true),
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Full re-download'),
              ),
              const SizedBox(height: 8),
              Text('Server: ${AppConfig.apiBaseUrl}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ]),
        ),
      ]),
    );
  }
}

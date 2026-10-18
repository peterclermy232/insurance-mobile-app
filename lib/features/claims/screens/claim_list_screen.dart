import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../data/claim_repository.dart';
import '../models/claim.dart';
import 'claim_detail_screen.dart';
import 'claim_form_screen.dart';

class ClaimListScreen extends StatefulWidget {
  const ClaimListScreen({super.key});

  @override
  State<ClaimListScreen> createState() => _ClaimListScreenState();
}

class _ClaimListScreenState extends State<ClaimListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ClaimRepository>();
    final canReport = context.watch<AuthController>().session?.canReportClaims ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Claims')),
      floatingActionButton: canReport
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClaimFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Report claim'),
            )
          : null,
      body: Column(children: [
        const StatusBanners(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search claim number, policy or farmer',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: DataBuilder<List<Claim>>(
            key: ValueKey(_query),
            changes: context.read<DataChanges>(),
            load: () => repo.list(query: _query),
            builder: (context, claims) {
              if (claims.isEmpty) {
                return const EmptyState(
                  icon: Icons.report_outlined,
                  title: 'No claims yet',
                  message: 'Claims can be reported on written or paid policies.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: claims.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final c = claims[i];
                  return Card(
                    child: ListTile(
                      title: Text('Claim ${c.numberLabel}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${c.farmerName ?? ''}  |  ${c.cause}\n'
                          '${Fmt.money(c.estimatedLoss)}  |  ${c.statusLabel}'),
                      isThreeLine: true,
                      trailing: SyncBadge(c.sync, compact: true),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => ClaimDetailScreen(uuid: c.uuid!))),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

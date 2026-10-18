import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../data/inspection_repository.dart';
import '../models/inspection.dart';
import 'inspection_detail_screen.dart';
import 'inspection_form_screen.dart';

class InspectionListScreen extends StatefulWidget {
  const InspectionListScreen({super.key});

  @override
  State<InspectionListScreen> createState() => _InspectionListScreenState();
}

class _InspectionListScreenState extends State<InspectionListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.read<InspectionRepository>();
    final canInspect = context.watch<AuthController>().session?.canInspect ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Inspections')),
      floatingActionButton: canInspect
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InspectionFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('New inspection'),
            )
          : null,
      body: Column(children: [
        const StatusBanners(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Search farm or farmer', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: DataBuilder<List<Inspection>>(
            key: ValueKey(_query),
            changes: context.read<DataChanges>(),
            load: () => repo.list(query: _query),
            builder: (context, items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'No inspections yet',
                  message: canInspect ? 'Create an inspection for a farm to start a field visit.' : null,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final x = items[i];
                  return Card(
                    child: ListTile(
                      title: Text('${x.typeLabel} - ${x.farmName ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${x.farmerName ?? ''}\n${x.scheduledDate ?? ''}  |  ${x.statusLabel}'),
                      isThreeLine: true,
                      trailing: SyncBadge(x.sync, compact: true),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => InspectionDetailScreen(uuid: x.uuid!))),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/db/syncable.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../data/farm_repository.dart';
import '../models/farm.dart';
import 'farm_detail_screen.dart';

/// All farms. With [onPick] it acts as a picker and returns the chosen farm.
class FarmListScreen extends StatefulWidget {
  const FarmListScreen({super.key, this.onPick, this.title = 'Farms'});

  final ValueChanged<Farm>? onPick;
  final String title;

  @override
  State<FarmListScreen> createState() => _FarmListScreenState();
}

class _FarmListScreenState extends State<FarmListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.read<FarmRepository>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        const StatusBanners(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search farm, farmer or location',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: DataBuilder<List<Farm>>(
            key: ValueKey(_query),
            changes: context.read<DataChanges>(),
            load: () => repo.list(query: _query),
            builder: (context, farms) {
              if (farms.isEmpty) {
                return EmptyState(
                  icon: Icons.landscape_outlined,
                  title: _query.isEmpty ? 'No farms yet' : 'No farms match "$_query"',
                  message: _query.isEmpty ? 'Farms are added from a farmer\'s page.' : null,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: farms.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final f = farms[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.landscape_outlined),
                      title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        f.farmerName ?? '',
                        f.sizeLabel,
                        if (f.locationLabel.isNotEmpty) f.locationLabel,
                      ].join('  |  ')),
                      trailing: SyncBadge(f.sync, compact: true),
                      onTap: () {
                        if (widget.onPick != null) {
                          widget.onPick!(f);
                        } else {
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => FarmDetailScreen(uuid: f.uuid!)));
                        }
                      },
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

/// Opens the farm list as a picker.
Future<Farm?> pickFarm(BuildContext context, {String title = 'Choose farm'}) {
  return Navigator.of(context).push<Farm>(MaterialPageRoute(
    builder: (ctx) => FarmListScreen(title: title, onPick: (f) => Navigator.of(ctx).pop(f)),
  ));
}

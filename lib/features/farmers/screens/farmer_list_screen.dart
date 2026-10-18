import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../data/farmer_repository.dart';
import '../models/farmer.dart';
import '../widgets/farmer_avatar.dart';
import 'farmer_detail_screen.dart';
import 'farmer_form_screen.dart';

class FarmerListScreen extends StatefulWidget {
  const FarmerListScreen({super.key});

  @override
  State<FarmerListScreen> createState() => _FarmerListScreenState();
}

class _FarmerListScreenState extends State<FarmerListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.read<FarmerRepository>();
    final canRegister = context.watch<AuthController>().session?.canRegisterFarmers ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Farmers')),
      floatingActionButton: canRegister
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const FarmerFormScreen())),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Register farmer'),
            )
          : null,
      body: Column(children: [
        const StatusBanners(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name, ID or phone',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: DataBuilder<List<Farmer>>(
            key: ValueKey(_query),
            changes: context.read<DataChanges>(),
            load: () => repo.list(query: _query),
            builder: (context, farmers) {
              if (farmers.isEmpty) {
                return EmptyState(
                  icon: Icons.people_outline,
                  title: _query.isEmpty ? 'No farmers yet' : 'No farmers match "$_query"',
                  message: _query.isEmpty
                      ? (canRegister
                          ? 'Register a farmer to get started. It works offline.'
                          : 'Farmers appear here after you sync.')
                      : null,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: farmers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => FarmerTile(farmers[i]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class FarmerTile extends StatelessWidget {
  const FarmerTile(this.farmer, {super.key});
  final Farmer farmer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: FarmerAvatar(initials: farmer.initials, localPath: farmer.localPhotoPath, url: farmer.photoUrl),
        title: Text(farmer.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ID ${farmer.idNumber}  |  ${farmer.phoneNumber}'),
          Text('${farmer.farmCount} farm${farmer.farmCount == 1 ? '' : 's'}', style: theme.textTheme.bodySmall),
          if (farmer.sync.needsAttention && farmer.sync.error != null)
            Text(farmer.sync.error!,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
        ]),
        trailing: SyncBadge(farmer.sync, compact: true),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => FarmerDetailScreen(uuid: farmer.uuid!))),
      ),
    );
  }
}

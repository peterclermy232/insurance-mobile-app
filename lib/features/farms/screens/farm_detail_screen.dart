import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../../farmers/screens/farmer_detail_screen.dart';
import '../../inspections/data/inspection_repository.dart';
import '../../inspections/models/inspection.dart';
import '../../inspections/screens/inspection_detail_screen.dart';
import '../../inspections/screens/inspection_form_screen.dart';
import '../../quotations/data/quotation_repository.dart';
import '../../quotations/models/quotation.dart';
import '../../quotations/screens/quotation_detail_screen.dart';
import '../../quotations/screens/quotation_form_screen.dart';
import '../data/admin_unit_repository.dart';
import '../data/farm_repository.dart';
import '../models/admin_unit.dart';
import '../models/farm.dart';
import 'farm_form_screen.dart';

class FarmDetailScreen extends StatelessWidget {
  const FarmDetailScreen({super.key, required this.uuid});

  final String uuid;

  Future<(Farm?, List<AdminUnit>, List<Quotation>, List<Inspection>)> _load(BuildContext context) async {
    final farms = context.read<FarmRepository>();
    final units = context.read<AdminUnitRepository>();
    final quotations = context.read<QuotationRepository>();
    final inspections = context.read<InspectionRepository>();
    final farm = await farms.get(uuid);
    final administrativeId = farm?.administrativeUnitId;
    final locationId = farm?.locationUnitId;
    final administrative = administrativeId == null ? <AdminUnit>[] : await units.path(administrativeId);
    final national = locationId == null ? <AdminUnit>[] : await units.path(locationId);
    return (
      farm,
      // County once, then sub-county / ward, then location / sub-location
      [...administrative, ...national.skip(administrative.isEmpty ? 0 : 1)],
      await quotations.list(farmUuid: uuid),
      await inspections.list(farmUuid: uuid),
    );
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthController>().session;
    return DataBuilder<(Farm?, List<AdminUnit>, List<Quotation>, List<Inspection>)>(
      changes: context.read<DataChanges>(),
      load: () => _load(context),
      builder: (context, data) {
        final (farm, locationPath, quotations, inspections) = data;
        if (farm == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.landscape_outlined, title: 'Farm not found'));
        }
        final canEdit = (session?.canRegisterFarmers ?? false) && farm.sync.canEditFromDevice;
        return Scaffold(
          appBar: AppBar(
            title: Text(farm.name),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: 'Edit farm',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _open(context, FarmFormScreen(uuid: uuid)),
                ),
            ],
          ),
          body: Column(children: [
            const StatusBanners(),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Align(alignment: Alignment.centerLeft, child: SyncBadge(farm.sync)),
                const SizedBox(height: 12),
                SyncStateBanner(
                  farm.sync,
                  onRetry: canEdit ? () => context.read<FarmRepository>().retryUpload(uuid) : null,
                ),
                SectionCard(title: 'Farm details', icon: Icons.landscape_outlined, children: [
                  if (farm.farmerName != null)
                    InkWell(
                      onTap: farm.farmerUuid == null
                          ? null
                          : () => _open(context, FarmerDetailScreen(uuid: farm.farmerUuid!)),
                      child: InfoRow('Farmer', farm.farmerName),
                    ),
                  InfoRow('Size', farm.sizeLabel),
                  if (locationPath.isNotEmpty)
                    for (final unit in locationPath) InfoRow(unit.levelLabel, unit.name)
                  else ...[
                    InfoRow('County', farm.county),
                    InfoRow('Sub-county', farm.subCounty),
                    InfoRow('Ward', farm.ward),
                  ],
                  InfoRow('Village', farm.village),
                  InfoRow('Clan', farm.clan),
                  InfoRow(
                    'GPS point',
                    farm.latitude == null
                        ? null
                        : '${Fmt.coord(farm.latitude)}, ${Fmt.coord(farm.longitude)}'
                            '${farm.gpsAccuracy == null ? '' : ' (+/- ${farm.gpsAccuracy!.round()} m)'}',
                  ),
                ]),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Quotations and policies',
                  icon: Icons.request_quote_outlined,
                  trailing: (session?.canQuote ?? false)
                      ? TextButton(
                          onPressed: () => _open(context, QuotationFormScreen(farmUuid: uuid)),
                          child: const Text('New quotation'),
                        )
                      : null,
                  children: [
                    if (quotations.isEmpty) const Text('None yet'),
                    for (final q in quotations)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(q.title),
                        subtitle: Text('${Fmt.money(q.sumInsured)}  |  ${q.statusLabel}'),
                        trailing: SyncBadge(q.sync, compact: true),
                        onTap: () => _open(context, QuotationDetailScreen(uuid: q.uuid!)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Inspections',
                  icon: Icons.fact_check_outlined,
                  trailing: (session?.canInspect ?? false)
                      ? TextButton(
                          onPressed: () => _open(context, InspectionFormScreen(farmUuid: uuid)),
                          child: const Text('New inspection'),
                        )
                      : null,
                  children: [
                    if (inspections.isEmpty) const Text('None yet'),
                    for (final i in inspections)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(i.typeLabel),
                        subtitle: Text('${i.scheduledDate ?? ''}  |  ${i.statusLabel}'),
                        trailing: SyncBadge(i.sync, compact: true),
                        onTap: () => _open(context, InspectionDetailScreen(uuid: i.uuid!)),
                      ),
                  ],
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

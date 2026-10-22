import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/photo_strip.dart';
import '../../../core/widgets/status_banners.dart';
import '../data/claim_repository.dart';
import '../models/claim.dart';
import 'claim_form_screen.dart';

class ClaimDetailScreen extends StatelessWidget {
  const ClaimDetailScreen({super.key, required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthController>().session;
    final repo = context.read<ClaimRepository>();
    final media = context.read<MediaRepository>();
    return DataBuilder<(Claim?, List<LocalPhoto>)>(
      changes: context.read<DataChanges>(),
      load: () async => (await repo.get(uuid), await media.forEntity(uuid)),
      builder: (context, data) {
        final (claim, photos) = data;
        if (claim == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Claim not found'));
        }
        final canEdit = (session?.canReportClaims ?? false) && claim.isEditable;
        return Scaffold(
          appBar: AppBar(
            title: Text('Claim ${claim.numberLabel}'),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: 'Edit claim',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClaimFormScreen(uuid: uuid))),
                ),
            ],
          ),
          body: Column(children: [
            const StatusBanners(),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  SyncBadge(claim.sync),
                  const SizedBox(width: 8),
                  StatusChip(claim.statusLabel),
                  if (claim.isAreaYield) ...[
                    const SizedBox(width: 8),
                    const StatusChip('Area yield'),
                  ],
                ]),
                const SizedBox(height: 12),
                SyncStateBanner(claim.sync, onRetry: canEdit ? () => repo.retryUpload(uuid) : null),
                SectionCard(title: 'Claim', icon: Icons.report_outlined, children: [
                  InfoRow('Claim number', claim.numberLabel),
                  InfoRow('Policy', claim.policyNumber ?? claim.productName),
                  InfoRow('Farmer', claim.farmerName),
                  InfoRow('Farm', claim.farmName),
                  InfoRow('Sum insured', Fmt.money(claim.sumInsured)),
                  InfoRow(claim.isAreaYield ? 'Calculated payout' : 'Estimated loss', Fmt.money(claim.estimatedLoss)),
                  if (claim.approvedAmount != null) InfoRow('Approved amount', Fmt.money(claim.approvedAmount)),
                  InfoRow('Status', claim.statusLabel),
                  InfoRow('Assessor', claim.assessorName),
                  InfoRow('Reported', Fmt.date(claim.claimDate ?? claim.createdAt)),
                ]),
                const SizedBox(height: 12),
                if (claim.areaYield case final area?)
                  SectionCard(title: 'Area yield payout', icon: Icons.grass_outlined, children: [
                    InfoRow('Area', area.area),
                    InfoRow('Guaranteed yield', area.yieldLabel(area.guaranteedYield)),
                    InfoRow('Actual yield', area.yieldLabel(area.actualYield)),
                    InfoRow('Payout', area.payoutPercentLabel),
                    InfoRow('Payout amount', area.payout == null ? null : Fmt.money(area.payout)),
                    const SizedBox(height: 4),
                    Text('Created automatically from the approved average yield of the area; '
                        "it does not depend on this farm's own harvest.",
                        style: Theme.of(context).textTheme.bodySmall),
                  ])
                else
                  SectionCard(title: 'Loss details', icon: Icons.notes_outlined, children: [
                    InfoRow('Cause', claim.cause),
                    InfoRow('Date of loss', Fmt.date(Fmt.parse(claim.dateOfLoss))),
                    InfoRow('Description', claim.description),
                    InfoRow(
                      'Location',
                      claim.latitude == null
                          ? null
                          : '${Fmt.coord(claim.latitude)}, ${Fmt.coord(claim.longitude)}'
                              '${claim.gpsAccuracy == null ? '' : ' (+/- ${claim.gpsAccuracy!.round()} m)'}',
                    ),
                  ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Photos (${photos.length})', icon: Icons.photo_library_outlined, children: [
                  PhotoStrip(
                    photos: photos.map(PhotoItem.saved).toList(),
                    emptyText: 'No photos on this device',
                    onAdd: canEdit ? (p) => media.add('claim', uuid, p) : null,
                  ),
                ]),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

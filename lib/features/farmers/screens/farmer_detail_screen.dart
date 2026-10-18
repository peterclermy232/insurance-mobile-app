import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../../claims/data/claim_repository.dart';
import '../../claims/models/claim.dart';
import '../../claims/screens/claim_detail_screen.dart';
import '../../claims/screens/claim_form_screen.dart';
import '../../farms/data/farm_repository.dart';
import '../../farms/models/farm.dart';
import '../../farms/screens/farm_detail_screen.dart';
import '../../farms/screens/farm_form_screen.dart';
import '../../quotations/data/quotation_repository.dart';
import '../../quotations/models/quotation.dart';
import '../../quotations/screens/quotation_detail_screen.dart';
import '../data/farmer_repository.dart';
import '../models/farmer.dart';
import '../widgets/farmer_avatar.dart';
import 'farmer_form_screen.dart';

class _FarmerBundle {
  _FarmerBundle(this.farmer, this.farms, this.quotations, this.claims);
  final Farmer? farmer;
  final List<Farm> farms;
  final List<Quotation> quotations;
  final List<Claim> claims;
}

class FarmerDetailScreen extends StatelessWidget {
  const FarmerDetailScreen({super.key, required this.uuid});

  final String uuid;

  Future<_FarmerBundle> _load(BuildContext context) async {
    final farmerRepo = context.read<FarmerRepository>();
    final farmRepo = context.read<FarmRepository>();
    final quotationRepo = context.read<QuotationRepository>();
    final claimRepo = context.read<ClaimRepository>();
    return _FarmerBundle(
      await farmerRepo.get(uuid),
      await farmRepo.list(farmerUuid: uuid),
      await quotationRepo.list(farmerUuid: uuid),
      await claimRepo.list(farmerUuid: uuid),
    );
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthController>().session;
    return DataBuilder<_FarmerBundle>(
      changes: context.read<DataChanges>(),
      load: () => _load(context),
      builder: (context, data) {
        final farmer = data.farmer;
        if (farmer == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.person_off_outlined, title: 'Farmer not found'),
          );
        }
        final canEdit = (session?.canRegisterFarmers ?? false) && farmer.sync.canEditFromDevice;
        return Scaffold(
          appBar: AppBar(
            title: Text(farmer.fullName),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: 'Edit farmer',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _open(context, FarmerFormScreen(uuid: uuid)),
                ),
            ],
          ),
          floatingActionButton: (session?.canRegisterFarmers ?? false)
              ? FloatingActionButton.extended(
                  onPressed: () => _open(context, FarmFormScreen(farmerUuid: uuid)),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Add farm'),
                )
              : null,
          body: Column(children: [
            const StatusBanners(),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                Row(children: [
                  FarmerAvatar(
                      initials: farmer.initials, localPath: farmer.localPhotoPath, url: farmer.photoUrl, radius: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(farmer.fullName, style: Theme.of(context).textTheme.titleLarge),
                      Text('ID ${farmer.idNumber}'),
                      const SizedBox(height: 6),
                      SyncBadge(farmer.sync),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                SyncStateBanner(
                  farmer.sync,
                  notice: farmer.notice,
                  onRetry: canEdit ? () => context.read<FarmerRepository>().retryUpload(uuid) : null,
                ),
                SectionCard(title: 'Details', icon: Icons.badge_outlined, children: [
                  InfoRow('Phone', farmer.phoneNumber),
                  InfoRow('Email', farmer.email),
                  InfoRow('Gender', farmer.genderLabel),
                  InfoRow('Date of birth', Fmt.date(Fmt.parse(farmer.dateOfBirth))),
                  InfoRow('Category', farmer.category),
                  InfoRow(
                    'Registered at',
                    farmer.latitude == null
                        ? null
                        : '${Fmt.coord(farmer.latitude)}, ${Fmt.coord(farmer.longitude)}'
                            '${farmer.gpsAccuracy == null ? '' : ' (+/- ${farmer.gpsAccuracy!.round()} m)'}',
                  ),
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Next of kin', icon: Icons.family_restroom, children: [
                  if (farmer.nextOfKin.isEmpty) const Text('None recorded'),
                  for (final k in farmer.nextOfKin)
                    InfoRow(k.relationship.isEmpty ? 'Next of kin' : k.relationship, '${k.name}  ${k.phoneNumber}'),
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Bank accounts', icon: Icons.account_balance_outlined, children: [
                  if (farmer.bankAccounts.isEmpty) const Text('None recorded'),
                  for (final b in farmer.bankAccounts) InfoRow(b.bankName, '${b.accountNumber}  ${b.accountName}'),
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Farms (${data.farms.length})', icon: Icons.landscape_outlined, children: [
                  if (data.farms.isEmpty) const Text('No farms yet'),
                  for (final f in data.farms)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.name),
                      subtitle: Text([f.sizeLabel, if (f.locationLabel.isNotEmpty) f.locationLabel].join('  |  ')),
                      trailing: SyncBadge(f.sync, compact: true),
                      onTap: () => _open(context, FarmDetailScreen(uuid: f.uuid!)),
                    ),
                ]),
                const SizedBox(height: 12),
                SectionCard(
                    title: 'Quotations and policies (${data.quotations.length})',
                    icon: Icons.request_quote_outlined,
                    children: [
                      if (data.quotations.isEmpty) const Text('None yet'),
                      for (final q in data.quotations)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(q.title),
                          subtitle: Text('${q.farmName ?? ''}  |  ${Fmt.money(q.sumInsured)}  |  ${q.statusLabel}'),
                          trailing: SyncBadge(q.sync, compact: true),
                          onTap: () => _open(context, QuotationDetailScreen(uuid: q.uuid!)),
                        ),
                    ]),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Claims (${data.claims.length})',
                  icon: Icons.report_outlined,
                  trailing: (session?.canReportClaims ?? false) && data.quotations.any((q) => q.isClaimable)
                      ? TextButton(
                          onPressed: () => _open(context, ClaimFormScreen(farmerUuid: uuid)),
                          child: const Text('Report claim'),
                        )
                      : null,
                  children: [
                    if (data.claims.isEmpty) const Text('None reported'),
                    for (final c in data.claims)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Claim ${c.numberLabel}'),
                        subtitle: Text('${c.cause}  |  ${Fmt.money(c.estimatedLoss)}  |  ${c.statusLabel}'),
                        trailing: SyncBadge(c.sync, compact: true),
                        onTap: () => _open(context, ClaimDetailScreen(uuid: c.uuid!)),
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

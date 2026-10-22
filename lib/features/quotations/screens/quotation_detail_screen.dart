import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../../claims/screens/claim_form_screen.dart';
import '../../farms/screens/farm_detail_screen.dart';
import '../data/quotation_repository.dart';
import '../models/quotation.dart';
import 'quotation_form_screen.dart';

class QuotationDetailScreen extends StatelessWidget {
  const QuotationDetailScreen({super.key, required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthController>().session;
    final repo = context.read<QuotationRepository>();
    return DataBuilder<Quotation?>(
      changes: context.read<DataChanges>(),
      load: () => repo.get(uuid),
      builder: (context, q) {
        if (q == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Quotation not found'));
        }
        final canEdit = (session?.canQuote ?? false) && q.isEditable;
        return Scaffold(
          appBar: AppBar(
            title: Text(q.title),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: 'Edit quotation',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => QuotationFormScreen(uuid: uuid))),
                ),
            ],
          ),
          body: Column(children: [
            const StatusBanners(),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  SyncBadge(q.sync),
                  const SizedBox(width: 8),
                  StatusChip(q.statusLabel),
                ]),
                const SizedBox(height: 12),
                SyncStateBanner(q.sync, onRetry: canEdit ? () => repo.retryUpload(uuid) : null),
                SectionCard(title: 'Quotation', icon: Icons.request_quote_outlined, children: [
                  InfoRow('Policy number', q.policyNumber ?? 'Not issued yet'),
                  InfoRow('Product', q.productName),
                  InkWell(
                    onTap: q.farmUuid == null
                        ? null
                        : () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => FarmDetailScreen(uuid: q.farmUuid!))),
                    child: InfoRow('Farm', q.farmName),
                  ),
                  InfoRow('Farmer', q.farmerName),
                  InfoRow('Sum insured', Fmt.money(q.sumInsured)),
                  if (q.premiumAmount != null)
                    InfoRow('Premium', Fmt.money(q.premiumAmount))
                  else
                    InfoRow('Premium (estimate)', '${Fmt.money(q.estimatedPremium)} - confirmed by the office'),
                  InfoRow('Status', q.statusLabel),
                  InfoRow('Date', Fmt.date(q.quotationDate ?? q.createdAt)),
                ]),
                if (q.isAreaYield) ...[
                  const SizedBox(height: 12),
                  SectionCard(title: 'Area yield cover', icon: Icons.grass_outlined, children: [
                    if (q.basisRiskNotice != null) Text(q.basisRiskNotice!),
                    const SizedBox(height: 8),
                    const Text(CalculationMethod.noClaimNeeded),
                  ]),
                ],
                if (q.isClaimable && (session?.canReportClaims ?? false)) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ClaimFormScreen(quotationUuid: uuid))),
                    icon: const Icon(Icons.report_outlined),
                    label: const Text('Report a claim on this policy'),
                  ),
                ],
              ]),
            ),
          ]),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_banners.dart';
import '../data/quotation_repository.dart';
import '../models/quotation.dart';
import 'quotation_detail_screen.dart';
import 'quotation_form_screen.dart';

class QuotationListScreen extends StatefulWidget {
  const QuotationListScreen({super.key});

  @override
  State<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends State<QuotationListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.read<QuotationRepository>();
    final canQuote = context.watch<AuthController>().session?.canQuote ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Quotations and policies')),
      floatingActionButton: canQuote
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuotationFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('New quotation'),
            )
          : null,
      body: Column(children: [
        const StatusBanners(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search policy, product, farm or farmer',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: DataBuilder<List<Quotation>>(
            key: ValueKey(_query),
            changes: context.read<DataChanges>(),
            load: () => repo.list(query: _query),
            builder: (context, items) {
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.request_quote_outlined,
                  title: 'No quotations yet',
                  message: 'Create a quotation from a farm, or sync to download policies.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final q = items[i];
                  return Card(
                    child: ListTile(
                      title: Text(q.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${q.farmerName ?? ''}  |  ${q.farmName ?? ''}\n'
                          '${Fmt.money(q.sumInsured)}  |  ${q.statusLabel}'),
                      isThreeLine: true,
                      trailing: SyncBadge(q.sync, compact: true),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => QuotationDetailScreen(uuid: q.uuid!))),
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

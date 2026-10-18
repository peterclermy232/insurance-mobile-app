import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_helpers.dart';
import '../../farms/data/farm_repository.dart';
import '../../farms/models/farm.dart';
import '../../farms/screens/farm_list_screen.dart';
import '../data/quotation_repository.dart';
import '../models/quotation.dart';

/// Enrol a farm on an insurance product (creates a quotation).
class QuotationFormScreen extends StatefulWidget {
  const QuotationFormScreen({super.key, this.farmUuid, this.uuid});

  final String? farmUuid;
  final String? uuid;

  @override
  State<QuotationFormScreen> createState() => _QuotationFormScreenState();
}

class _QuotationFormScreenState extends State<QuotationFormScreen> {
  final _form = GlobalKey<FormState>();
  final _sumInsured = TextEditingController();
  List<InsuranceProduct> _products = [];
  InsuranceProduct? _product;
  Farm? _farm;
  Quotation? _existing;
  bool _loading = true;
  bool _saving = false;

  bool get _isEdit => widget.uuid != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<QuotationRepository>();
    final farms = context.read<FarmRepository>();
    _products = await repo.activeProducts();
    var farmUuid = widget.farmUuid;
    if (_isEdit) {
      _existing = await repo.get(widget.uuid!);
      if (_existing != null) {
        farmUuid = _existing!.farmUuid;
        _sumInsured.text = _existing!.sumInsured.toStringAsFixed(0);
        _product = _products.where((p) => p.id == _existing!.productId).firstOrNull;
      }
    }
    if (farmUuid != null) _farm = await farms.get(farmUuid);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _sumInsured.dispose();
    super.dispose();
  }

  double? get _sum => parseAmount(_sumInsured.text);

  Future<void> _chooseFarm() async {
    final farm = await pickFarm(context);
    if (farm != null) setState(() => _farm = farm);
  }

  Future<void> _save() async {
    if (_farm == null) {
      showMessage(context, 'Choose the farm to insure.', error: true);
      return;
    }
    if (!_form.currentState!.validate()) return;
    final product = _product!;
    final sum = _sum!;
    final ok = await confirm(context,
        title: 'Save quotation?',
        message: 'Insure ${_farm!.name} under ${product.name} for ${Fmt.money(sum)}.\n\n'
            'Estimated premium: ${Fmt.money(product.estimatePremium(sum))} (the office confirms the final amount).',
        confirmLabel: 'Save');
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final repo = context.read<QuotationRepository>();
    try {
      if (_isEdit) {
        await repo.update(widget.uuid!, farmUuid: _farm!.uuid!, product: product, sumInsured: sum);
      } else {
        await repo.create(farmUuid: _farm!.uuid!, product: product, sumInsured: sum);
      }
      if (!mounted) return;
      showMessage(context, 'Quotation saved on this device.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
    if (_existing != null && !_existing!.isEditable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quotation')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'This quotation can no longer be changed',
          message: 'The office has already processed it.',
        ),
      );
    }
    final product = _product;
    final sum = _sum;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit quotation' : 'New quotation')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SectionCard(title: 'Farm', icon: Icons.landscape_outlined, children: [
            if (_farm == null)
              OutlinedButton.icon(onPressed: _chooseFarm, icon: const Icon(Icons.search), label: const Text('Choose farm'))
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_farm!.name),
                subtitle: Text('${_farm!.farmerName ?? ''}  |  ${_farm!.sizeLabel}'),
                trailing: widget.farmUuid == null && !_isEdit
                    ? TextButton(onPressed: _chooseFarm, child: const Text('Change'))
                    : null,
              ),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Insurance product', icon: Icons.shield_outlined, children: [
            if (_products.isEmpty)
              const Text('No active insurance products on this device yet. Sync once while online to download them.')
            else ...[
              DropdownButtonFormField<InsuranceProduct>(
                value: product,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Product *'),
                items: [
                  for (final p in _products)
                    DropdownMenuItem(
                      value: p,
                      child: Text(
                        p.cropSeasonLabel.isEmpty ? p.name : '${p.name} - ${p.cropSeasonLabel}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (p) => setState(() => _product = p),
                validator: (v) => v == null ? 'Choose a product' : null,
              ),
              if (product != null) ...[
                const SizedBox(height: 8),
                InfoRow('Crop', product.varietyName == null ? product.cropName : '${product.cropName} (${product.varietyName})'),
                InfoRow('Season', product.seasonName),
                InfoRow('Category', product.categoryName),
                InfoRow('Premium rate', '${product.premiumRate.toStringAsFixed(2)}%'),
                if (product.defaultSumInsured != null)
                  InfoRow('Reference sum insured', Fmt.money(product.defaultSumInsured)),
              ],
            ],
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Cover', icon: Icons.payments_outlined, children: [
            TextFormField(
              controller: _sumInsured,
              decoration: const InputDecoration(labelText: 'Sum insured (KES) *', prefixText: 'KES '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validators.positiveNumber('Sum insured'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Estimated premium', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  (product != null && sum != null && sum > 0) ? Fmt.money(product.estimatePremium(sum)) : '-',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('Estimate - confirmed by the office', style: theme.textTheme.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_saving || _products.isEmpty) ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_isEdit ? 'Save changes' : 'Save quotation'),
          ),
        ]),
      ),
    );
  }
}

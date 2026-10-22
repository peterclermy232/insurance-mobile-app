import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_helpers.dart';
import '../../farms/data/admin_unit_repository.dart';
import '../../farms/data/farm_repository.dart';
import '../../farms/models/admin_unit.dart';
import '../../farms/models/farm.dart';
import '../../farms/screens/farm_form_screen.dart';
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

  /// Area yield products: the officer has read the basis risk notice to the farmer.
  bool _explained = false;

  /// Area yield products: the farm's unit at the product's area level (null when it has none).
  AdminUnit? _farmArea;

  /// The farm's unit is set but not in the downloaded location tree, so its
  /// level can't be checked on the device (the server checks it).
  bool _areaUnknown = false;

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
    await _checkArea();
    if (mounted) setState(() => _loading = false);
  }

  /// Finds the farm's ward / sub-county / county for an area yield product.
  Future<void> _checkArea() async {
    _farmArea = null;
    _areaUnknown = false;
    final unitId = _farm?.administrativeUnitId;
    final level = _product?.areaLevel;
    if (_product?.isAreaYield != true || unitId == null || level == null) return;
    final path = await context.read<AdminUnitRepository>().path(unitId);
    if (path.isEmpty) {
      _areaUnknown = true;
    } else {
      _farmArea = path.where((u) => u.level == level).firstOrNull;
    }
  }

  /// The farm can't be sold this product until its location is set deep enough.
  bool get _missingArea {
    final product = _product;
    if (product == null || !product.isAreaYield || _farm == null) return false;
    if (_farm!.administrativeUnitId == null) return true;
    if (product.areaLevel == null || _areaUnknown) return false;
    return _farmArea == null;
  }

  String get _missingAreaMessage =>
      '${_product!.name} pays by ${_product!.areaLabel}. Set the farm\'s ${_product!.areaLabel} before selling it.';

  Future<void> _selectProduct(InsuranceProduct? p) async {
    setState(() {
      _product = p;
      _explained = false;
    });
    await _checkArea();
    if (mounted) setState(() {});
  }

  Future<void> _editFarm() async {
    final uuid = _farm?.uuid;
    if (uuid == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FarmFormScreen(uuid: uuid)));
    if (!mounted) return;
    _farm = await context.read<FarmRepository>().get(uuid);
    await _checkArea();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sumInsured.dispose();
    super.dispose();
  }

  double? get _sum => parseAmount(_sumInsured.text);

  Future<void> _chooseFarm() async {
    final farm = await pickFarm(context);
    if (farm == null) return;
    setState(() => _farm = farm);
    await _checkArea();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_farm == null) {
      showMessage(context, 'Choose the farm to insure.', error: true);
      return;
    }
    if (!_form.currentState!.validate()) return;
    final product = _product!;
    final sum = _sum!;
    if (_missingArea) {
      showMessage(context, _missingAreaMessage, error: true);
      return;
    }
    if (product.isAreaYield && !_explained) {
      showMessage(context, 'Explain how area yield cover pays to the farmer and tick the box before saving.',
          error: true);
      return;
    }
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
                onChanged: _selectProduct,
                validator: (v) => v == null ? 'Choose a product' : null,
              ),
              if (product != null) ...[
                const SizedBox(height: 8),
                InfoRow('Crop', product.varietyName == null ? product.cropName : '${product.cropName} (${product.varietyName})'),
                InfoRow('Season', product.seasonName),
                InfoRow('Category', product.categoryName),
                if (product.coverTypeName != null) InfoRow('Cover type', product.coverTypeName),
                InfoRow('Premium rate', '${product.premiumRate.toStringAsFixed(2)}%'),
                if (product.defaultSumInsured != null)
                  InfoRow('Reference sum insured', Fmt.money(product.defaultSumInsured)),
              ],
            ],
          ]),
          if (product != null && product.isAreaYield) ...[
            const SizedBox(height: 12),
            _areaYieldCard(theme, product),
          ],
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
            onPressed: (_saving || _products.isEmpty || _missingArea) ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_isEdit ? 'Save changes' : 'Save quotation'),
          ),
        ]),
      ),
    );
  }

  /// Basis risk warning for the farmer, the explained-to-farmer tick and the farm location check.
  Widget _areaYieldCard(ThemeData theme, InsuranceProduct product) {
    const color = AppTheme.warning;
    final terms = product.coverageTerms;
    final farm = _farm;
    final canEditFarm = farm?.uuid != null && farm!.sync.canEditFromDevice;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Area yield cover - explain to the farmer',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(product.basisRiskNotice),
        if (terms != null) ...[
          const SizedBox(height: 8),
          Text(terms, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 4),
        const Text('No claim is reported for this cover: payouts are made automatically once the '
            "area's yield has been measured and approved."),
        if (farm != null) ...[
          const SizedBox(height: 8),
          if (_missingArea) ...[
            Text(_missingAreaMessage, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
            if (canEditFarm)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _editFarm,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Edit farm location'),
                ),
              )
            else
              const Text('Ask the office to set the farm\'s location.'),
          ] else if (_farmArea != null)
            Text('This farm is paid on the average of ${_farmArea!.name} ${_farmArea!.levelLabel.toLowerCase()}.'),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _explained,
          onChanged: (v) => setState(() => _explained = v ?? false),
          title: const Text('I have explained this to the farmer'),
        ),
      ]),
    );
  }
}

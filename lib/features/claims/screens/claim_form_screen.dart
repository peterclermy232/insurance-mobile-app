import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/location/location_service.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_helpers.dart';
import '../../../core/widgets/gps_capture.dart';
import '../../../core/widgets/photo_strip.dart';
import '../../quotations/data/quotation_repository.dart';
import '../../quotations/models/quotation.dart';
import '../data/claim_repository.dart';
import '../models/claim.dart';
import 'claim_detail_screen.dart';

/// Report a loss on a written or paid policy.
class ClaimFormScreen extends StatefulWidget {
  const ClaimFormScreen({super.key, this.quotationUuid, this.farmerUuid, this.uuid});

  final String? quotationUuid;
  final String? farmerUuid;
  final String? uuid;

  @override
  State<ClaimFormScreen> createState() => _ClaimFormScreenState();
}

class _ClaimFormScreenState extends State<ClaimFormScreen> {
  final _form = GlobalKey<FormState>();
  final _loss = TextEditingController();
  final _description = TextEditingController();
  List<Quotation> _policies = [];
  Quotation? _policy;
  String? _cause;
  DateTime _dateOfLoss = DateTime.now();
  GeoFix? _gps;
  final List<CapturedPhoto> _newPhotos = [];
  List<LocalPhoto> _savedPhotos = [];
  Claim? _existing;
  bool _loading = true;
  bool _saving = false;

  /// Written / paid area yield policies left out of the picker (paid automatically).
  int _areaYieldPolicies = 0;

  bool get _isEdit => widget.uuid != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final quotations = context.read<QuotationRepository>();
    final claims = context.read<ClaimRepository>();
    final media = context.read<MediaRepository>();
    final claimable = await quotations.list(claimableOnly: true, farmerUuid: widget.farmerUuid);
    _policies = claimable.where((p) => !p.isAreaYield).toList();
    _areaYieldPolicies = claimable.length - _policies.length;
    var policyUuid = widget.quotationUuid;
    if (_isEdit) {
      _existing = await claims.get(widget.uuid!);
      final c = _existing;
      if (c != null) {
        policyUuid = c.quotationUuid;
        _loss.text = c.estimatedLoss.toStringAsFixed(0);
        _description.text = c.description;
        _cause = Claim.causes.contains(c.cause) ? c.cause : 'Other';
        _dateOfLoss = DateTime.tryParse(c.dateOfLoss ?? '') ?? _dateOfLoss;
        if (c.latitude != null && c.longitude != null) {
          _gps = GeoFix(latitude: c.latitude!, longitude: c.longitude!, accuracy: c.gpsAccuracy);
        }
        _savedPhotos = await media.forEntity(widget.uuid!);
        // A policy the office has since moved on is still shown for this claim.
        if (policyUuid != null && !_policies.any((p) => p.uuid == policyUuid)) {
          final p = await quotations.get(policyUuid);
          if (p != null) _policies = [p, ..._policies];
        }
      }
    }
    _policy = _policies.where((p) => p.uuid == policyUuid).firstOrNull ??
        (_policies.length == 1 ? _policies.first : null);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _loss.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfLoss,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      helpText: 'Date of loss',
    );
    if (picked != null) setState(() => _dateOfLoss = picked);
  }

  Future<void> _removeSaved(PhotoItem item) async {
    final ok = await confirm(context, title: 'Remove photo?', message: 'This photo has not been uploaded yet.',
        confirmLabel: 'Remove', destructive: true);
    if (!ok || !mounted) return;
    final media = context.read<MediaRepository>();
    await media.removePending(item.saved!.uuid);
    final refreshed = await media.forEntity(widget.uuid!);
    if (mounted) setState(() => _savedPhotos = refreshed);
  }

  Future<void> _save() async {
    if (_policy == null) {
      showMessage(context, 'Choose the policy for this claim.', error: true);
      return;
    }
    if (!_form.currentState!.validate()) {
      showMessage(context, 'Please correct the highlighted fields.', error: true);
      return;
    }
    if (_gps == null) {
      final proceed = await confirm(context,
          title: 'No GPS location', message: 'The loss location has not been captured. Save without it?',
          confirmLabel: 'Save anyway');
      if (!proceed || !mounted) return;
    }
    if (_newPhotos.isEmpty && _savedPhotos.isEmpty) {
      final proceed = await confirm(context,
          title: 'No photos', message: 'Photos of the damage help the claim. Save without photos?',
          confirmLabel: 'Save anyway');
      if (!proceed || !mounted) return;
    }
    setState(() => _saving = true);
    final repo = context.read<ClaimRepository>();
    final media = context.read<MediaRepository>();
    final claim = Claim(
      quotationUuid: _policy!.uuid,
      estimatedLoss: parseAmount(_loss.text)!,
      cause: _cause!,
      description: _description.text,
      dateOfLoss: Fmt.isoDate(_dateOfLoss),
      latitude: _gps?.latitude,
      longitude: _gps?.longitude,
      gpsAccuracy: _gps?.accuracy,
    );
    try {
      final String uuid;
      if (_isEdit) {
        uuid = widget.uuid!;
        await repo.update(uuid, claim);
      } else {
        uuid = await repo.create(claim);
      }
      for (final p in _newPhotos) {
        await media.add('claim', uuid, p);
      }
      if (!mounted) return;
      showMessage(context, 'Claim saved on this device. The claim number is assigned after sync.');
      if (_isEdit) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ClaimDetailScreen(uuid: uuid)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
    if (_existing != null && !_existing!.isEditable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Claim')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'This claim can no longer be changed',
          message: 'The office is already processing it.',
        ),
      );
    }
    if (_policies.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report claim')),
        body: EmptyState(
          icon: Icons.policy_outlined,
          title: 'No policies to claim on',
          message: 'Claims can only be reported on written or paid policies. '
              'Sync to download the latest policies from the office.'
              '${_areaYieldPolicies > 0 ? '\n\n${CalculationMethod.noClaimNeeded}' : ''}',
        ),
      );
    }
    final policy = _policy;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit claim' : 'Report claim')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SectionCard(title: 'Policy', icon: Icons.policy_outlined, children: [
            DropdownButtonFormField<Quotation>(
              value: policy,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Policy *'),
              items: [
                for (final p in _policies)
                  DropdownMenuItem(
                    value: p,
                    child: Text('${p.title} - ${p.farmerName ?? ''} (${p.farmName ?? ''})', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _isEdit ? null : (p) => setState(() => _policy = p),
              validator: (v) => v == null ? 'Choose a policy' : null,
            ),
            if (_areaYieldPolicies > 0 && !_isEdit) ...[
              const SizedBox(height: 8),
              Text(
                '$_areaYieldPolicies area yield ${_areaYieldPolicies == 1 ? 'policy is' : 'policies are'} not listed. '
                '${CalculationMethod.noClaimNeeded}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (policy != null) ...[
              const SizedBox(height: 8),
              InfoRow('Product', policy.productName),
              InfoRow('Sum insured', Fmt.money(policy.sumInsured)),
              InfoRow('Status', policy.statusLabel),
            ],
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Loss', icon: Icons.report_outlined, children: [
            DropdownButtonFormField<String>(
              value: _cause,
              decoration: const InputDecoration(labelText: 'Cause of loss *'),
              items: [for (final c in Claim.causes) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _cause = v),
              validator: (v) => v == null ? 'Choose the cause of loss' : null,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of loss *',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(Fmt.date(_dateOfLoss)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _loss,
              decoration: InputDecoration(
                labelText: 'Estimated loss (KES) *',
                prefixText: 'KES ',
                helperText: policy == null ? null : 'Cannot exceed the sum insured of ${Fmt.money(policy.sumInsured)}',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validators.positiveNumber(
                'Estimated loss',
                max: policy?.sumInsured,
                maxMessage: policy == null ? null : 'Cannot exceed the sum insured (${Fmt.money(policy.sumInsured)})',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description of the damage *',
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().length < 10) ? 'Describe the damage (at least 10 characters)' : null,
            ),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Location', icon: Icons.place_outlined, children: [
            GpsCapture(
              label: 'Loss location',
              initial: _gps,
              autoCapture: !_isEdit,
              onChanged: (fix) => setState(() => _gps = fix),
            ),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Photos of the damage', icon: Icons.photo_camera_outlined, children: [
            PhotoStrip(
              photos: [
                ..._savedPhotos.map(PhotoItem.saved),
                ..._newPhotos.map(PhotoItem.captured),
              ],
              onAdd: (p) => setState(() => _newPhotos.add(p)),
              onRemove: (item) {
                if (item.captured != null) {
                  setState(() => _newPhotos.remove(item.captured));
                } else {
                  _removeSaved(item);
                }
              },
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_isEdit ? 'Save changes' : 'Save claim'),
          ),
        ]),
      ),
    );
  }
}

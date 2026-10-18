import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/db/syncable.dart';
import '../../../core/location/location_service.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/photo_strip.dart';
import '../../../core/widgets/status_banners.dart';
import '../data/inspection_repository.dart';
import '../models/inspection.dart';

/// Carry out an inspection: check in, record findings and photos, check out.
class InspectionDetailScreen extends StatefulWidget {
  const InspectionDetailScreen({super.key, required this.uuid});

  final String uuid;

  @override
  State<InspectionDetailScreen> createState() => _InspectionDetailScreenState();
}

class _InspectionDetailScreenState extends State<InspectionDetailScreen> {
  final _notes = TextEditingController();
  final _recommendations = TextEditingController();
  Inspection? _inspection;
  List<LocalPhoto> _photos = [];
  String? _condition;
  double _damage = 0;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  late final DataChanges _changes;

  @override
  void initState() {
    super.initState();
    _changes = context.read<DataChanges>()..addListener(_load);
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<InspectionRepository>();
    final media = context.read<MediaRepository>();
    final inspection = await repo.get(widget.uuid);
    final photos = await media.forEntity(widget.uuid);
    if (!mounted) return;
    setState(() {
      _inspection = inspection;
      _photos = photos;
      if (inspection != null && !_dirty) {
        _condition = Inspection.cropConditions.contains(inspection.cropCondition) ? inspection.cropCondition : null;
        _damage = (inspection.damagePercent ?? 0).clamp(0, 100).toDouble();
        _notes.text = inspection.notes;
        _recommendations.text = inspection.recommendations;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _changes.removeListener(_load);
    _notes.dispose();
    _recommendations.dispose();
    super.dispose();
  }

  Inspection _withEdits(Inspection i, {
    String? status,
    GeoFix? checkIn,
    GeoFix? checkOut,
    DateTime? completedAt,
  }) {
    final now = DateTime.now();
    return Inspection(
      farmUuid: i.farmUuid,
      type: i.type,
      status: status ?? i.status,
      scheduledDate: i.scheduledDate,
      scheduledTime: i.scheduledTime,
      completedAt: completedAt ?? i.completedAt,
      checkInLat: checkIn?.latitude ?? i.checkInLat,
      checkInLon: checkIn?.longitude ?? i.checkInLon,
      checkInTime: checkIn != null ? now : i.checkInTime,
      checkOutLat: checkOut?.latitude ?? i.checkOutLat,
      checkOutLon: checkOut?.longitude ?? i.checkOutLon,
      checkOutTime: checkOut != null ? now : i.checkOutTime,
      findings: {
        ...i.findings,
        if (_condition != null) 'crop_condition': _condition,
        'damage_percent': _damage.round(),
        'notes': _notes.text.trim(),
      },
      recommendations: _recommendations.text.trim(),
    );
  }

  Future<GeoFix?> _gps() async {
    try {
      return await context.read<LocationService>().current();
    } on LocationFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
      return null;
    }
  }

  Future<void> _checkIn() async {
    setState(() => _busy = true);
    final fix = await _gps();
    if (fix != null && mounted) {
      await context
          .read<InspectionRepository>()
          .update(widget.uuid, _withEdits(_inspection!, status: 'IN_PROGRESS', checkIn: fix));
      if (mounted) showMessage(context, 'Checked in (${fix.accuracyLabel}).');
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _saveFindings({bool quiet = false}) async {
    await context.read<InspectionRepository>().update(widget.uuid, _withEdits(_inspection!));
    _dirty = false;
    if (mounted && !quiet) showMessage(context, 'Findings saved on this device.');
    await _load();
  }

  Future<void> _checkOut() async {
    if (_condition == null) {
      showMessage(context, 'Record the crop condition before checking out.', error: true);
      return;
    }
    final ok = await confirm(context,
        title: 'Complete inspection?',
        message: 'Checking out records your location and marks the inspection completed. '
            'Findings cannot be changed afterwards.',
        confirmLabel: 'Check out');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final fix = await _gps();
    if (fix != null && mounted) {
      await context.read<InspectionRepository>().update(
          widget.uuid,
          _withEdits(_inspection!, status: 'COMPLETED', checkOut: fix, completedAt: DateTime.now()));
      _dirty = false;
      if (mounted) showMessage(context, 'Inspection completed.');
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _addPhoto(CapturedPhoto photo) async {
    await context.read<MediaRepository>().add('inspection', widget.uuid, photo);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
    final i = _inspection;
    if (i == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Inspection not found'));
    }
    final canInspect = context.watch<AuthController>().session?.canInspect ?? false;
    final editable = canInspect && i.isEditable;
    final canRecord = editable && i.isCheckedIn;
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_dirty,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final leave = await confirm(context,
            title: 'Unsaved findings', message: 'Save your findings before leaving?', confirmLabel: 'Save');
        if (!context.mounted) return;
        if (leave) await _saveFindings(quiet: true);
        _dirty = false;
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(i.typeLabel)),
        body: Column(children: [
          const StatusBanners(),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [SyncBadge(i.sync), const SizedBox(width: 8), StatusChip(i.statusLabel)]),
              const SizedBox(height: 12),
              SyncStateBanner(
                i.sync,
                onRetry: editable ? () => context.read<InspectionRepository>().retryUpload(widget.uuid) : null,
              ),
              SectionCard(title: 'Visit', icon: Icons.event_outlined, children: [
                InfoRow('Farm', i.farmName),
                InfoRow('Farmer', i.farmerName),
                InfoRow('Scheduled', '${i.scheduledDate ?? ''} ${i.scheduledTime ?? ''}'.trim()),
                InfoRow('Inspector', i.inspectorName),
                InfoRow(
                    'Check-in',
                    i.checkInTime == null
                        ? null
                        : '${Fmt.dateTime(i.checkInTime)}\n${Fmt.coord(i.checkInLat)}, ${Fmt.coord(i.checkInLon)}'),
                InfoRow(
                    'Check-out',
                    i.checkOutTime == null
                        ? null
                        : '${Fmt.dateTime(i.checkOutTime)}\n${Fmt.coord(i.checkOutLat)}, ${Fmt.coord(i.checkOutLon)}'),
                if (editable && !i.isCheckedIn) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _checkIn,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: const Text('Check in at the farm'),
                  ),
                  const SizedBox(height: 4),
                  Text('Records your GPS position and the time.', style: theme.textTheme.bodySmall),
                ],
              ]),
              const SizedBox(height: 12),
              SectionCard(title: 'Findings', icon: Icons.assignment_outlined, children: [
                if (!canRecord && !i.isCheckedOut && editable)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Check in to record findings.'),
                  ),
                DropdownButtonFormField<String>(
                  value: _condition,
                  decoration: const InputDecoration(labelText: 'Crop condition'),
                  items: [for (final c in Inspection.cropConditions) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: canRecord ? (v) => setState(() {
                        _condition = v;
                        _dirty = true;
                      }) : null,
                ),
                const SizedBox(height: 12),
                Text('Damage: ${_damage.round()}%', style: theme.textTheme.labelLarge),
                Slider(
                  value: _damage,
                  max: 100,
                  divisions: 20,
                  label: '${_damage.round()}%',
                  onChanged: canRecord ? (v) => setState(() {
                        _damage = v;
                        _dirty = true;
                      }) : null,
                ),
                TextField(
                  controller: _notes,
                  enabled: canRecord,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
                  onChanged: (_) => _dirty = true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _recommendations,
                  enabled: canRecord,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Recommendations', alignLabelWithHint: true),
                  onChanged: (_) => _dirty = true,
                ),
                if (canRecord) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _saveFindings,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save findings'),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              SectionCard(title: 'Photos (${_photos.length})', icon: Icons.photo_library_outlined, children: [
                PhotoStrip(
                  photos: _photos.map(PhotoItem.saved).toList(),
                  onAdd: canRecord ? _addPhoto : null,
                  emptyText: canRecord ? 'No photos yet' : 'No photos on this device',
                ),
              ]),
              if (canRecord) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _checkOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Check out and complete'),
                ),
              ],
              const SizedBox(height: 24),
            ]),
          ),
        ]),
      ),
    );
  }
}

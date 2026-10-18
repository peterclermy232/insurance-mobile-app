import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/location/location_service.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_helpers.dart';
import '../../../core/widgets/gps_capture.dart';
import '../../farmers/data/farmer_repository.dart';
import '../data/admin_unit_repository.dart';
import '../data/farm_repository.dart';
import '../models/admin_unit.dart';
import '../models/farm.dart';
import '../models/kenya_counties.dart';

/// Add a farm under a farmer, or edit one.
class FarmFormScreen extends StatefulWidget {
  const FarmFormScreen({super.key, this.farmerUuid, this.uuid}) : assert(farmerUuid != null || uuid != null);

  final String? farmerUuid;
  final String? uuid;

  @override
  State<FarmFormScreen> createState() => _FarmFormScreenState();
}

class _FarmFormScreenState extends State<FarmFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _size = TextEditingController();
  final _county = TextEditingController();
  final _subCounty = TextEditingController();
  final _ward = TextEditingController();
  final _village = TextEditingController();
  final _clan = TextEditingController();
  // Downloaded location tree: a county, then two branches under it
  List<AdminUnit> _counties = [];
  AdminUnit? _countyUnit;
  final Map<_Branch, List<_LocationLevel>> _branches = {for (final b in _Branch.values) b: []};
  // False until the office loads locations and the device syncs; the old free-text fields are shown instead
  bool _hasLocationTree = false;
  String _unit = 'ACRES';
  GeoFix? _gps;
  String? _farmerUuid;
  String? _farmerName;
  Farm? _existing;
  bool _loading = true;
  bool _saving = false;

  bool get _isEdit => widget.uuid != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final farmRepo = context.read<FarmRepository>();
    final farmerRepo = context.read<FarmerRepository>();
    final unitRepo = context.read<AdminUnitRepository>();
    _farmerUuid = widget.farmerUuid;
    if (_isEdit) {
      final farm = await farmRepo.get(widget.uuid!);
      if (farm != null) {
        _existing = farm;
        _farmerUuid = farm.farmerUuid;
        _name.text = farm.name;
        _size.text = farm.size == null ? '' : farm.size!.toString();
        _unit = Farm.units.containsKey(farm.unit) ? farm.unit : 'ACRES';
        _county.text = farm.county ?? '';
        _subCounty.text = farm.subCounty ?? '';
        _ward.text = farm.ward ?? '';
        _village.text = farm.village ?? '';
        _clan.text = farm.clan ?? '';
        if (farm.latitude != null && farm.longitude != null) {
          _gps = GeoFix(latitude: farm.latitude!, longitude: farm.longitude!, accuracy: farm.gpsAccuracy);
        }
      }
    }
    if (_farmerUuid != null) _farmerName = (await farmerRepo.get(_farmerUuid!))?.fullName;
    await _loadLocations(unitRepo, _existing?.administrativeUnitId, _existing?.locationUnitId);
    if (mounted) setState(() => _loading = false);
  }

  /// Builds the dropdowns, pre-selecting a saved farm's units.
  Future<void> _loadLocations(AdminUnitRepository repo, int? administrativeId, int? locationId) async {
    _counties = await repo.topLevel();
    _hasLocationTree = _counties.isNotEmpty;
    if (!_hasLocationTree) return;
    final paths = {
      _Branch.administrative: administrativeId == null ? <AdminUnit>[] : await repo.path(administrativeId),
      _Branch.national: locationId == null ? <AdminUnit>[] : await repo.path(locationId),
    };
    final county = paths.values.where((p) => p.isNotEmpty).firstOrNull?.first;
    _countyUnit = _counties.where((c) => c.id == county?.id).firstOrNull;
    if (_countyUnit == null) return;
    for (final branch in _Branch.values) {
      // Path is county first; the branch's own dropdowns start below it
      final units = paths[branch]!.skip(1).toList();
      final first = await repo.children(_countyUnit!.id, level: branch.firstLevel);
      if (first.isEmpty) continue;
      final levels = [_LocationLevel(first, units.firstOrNull)];
      for (var i = 0; i < units.length; i++) {
        final children = await repo.children(units[i].id);
        if (children.isEmpty) break;
        levels.add(_LocationLevel(children, i + 1 < units.length ? units[i + 1] : null));
      }
      _branches[branch] = levels;
    }
  }

  Future<void> _onCountySelected(AdminUnit? county) async {
    setState(() {
      _countyUnit = county;
      for (final b in _Branch.values) {
        _branches[b] = [];
      }
    });
    if (county == null) return;
    final repo = context.read<AdminUnitRepository>();
    for (final branch in _Branch.values) {
      final first = await repo.children(county.id, level: branch.firstLevel);
      // Ignore if the county changed while this was loading
      if (!mounted || _countyUnit?.id != county.id) return;
      if (first.isNotEmpty) setState(() => _branches[branch] = [_LocationLevel(first, null)]);
    }
  }

  Future<void> _onUnitSelected(_Branch branch, int index, AdminUnit? unit) async {
    final current = _branches[branch]!;
    setState(() => _branches[branch] = [...current.take(index), _LocationLevel(current[index].options, unit)]);
    if (unit == null) return;
    final children = await context.read<AdminUnitRepository>().children(unit.id);
    final levels = _branches[branch]!;
    // Ignore if the user changed this level again while children were loading
    if (!mounted || levels.length != index + 1 || levels[index].selected?.id != unit.id) return;
    if (children.isNotEmpty) setState(() => _branches[branch] = [...levels, _LocationLevel(children, null)]);
  }

  /// Deepest unit picked in a branch
  int? _selectedId(_Branch branch) =>
      _branches[branch]!.lastWhere((l) => l.selected != null, orElse: () => _LocationLevel.none).selected?.id;

  @override
  void dispose() {
    for (final c in [_name, _size, _county, _subCounty, _ward, _village, _clan]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      showMessage(context, 'Please correct the highlighted fields.', error: true);
      return;
    }
    if (_gps == null) {
      final proceed = await confirm(context,
          title: 'No GPS point', message: 'The farm location has not been captured. Save without it?',
          confirmLabel: 'Save anyway');
      if (!proceed || !mounted) return;
    }
    setState(() => _saving = true);
    final repo = context.read<FarmRepository>();
    final farm = Farm(
      farmerUuid: _farmerUuid,
      name: _name.text,
      size: parseAmount(_size.text),
      unit: _unit,
      // The free-text fields are left as they were once the location tree is in use
      county: _hasLocationTree ? _existing?.county : _county.text,
      subCounty: _hasLocationTree ? _existing?.subCounty : _subCounty.text,
      ward: _hasLocationTree ? _existing?.ward : _ward.text,
      // A county alone still records where the farm is
      administrativeUnitId: _hasLocationTree
          ? (_selectedId(_Branch.administrative) ?? _countyUnit?.id)
          : _existing?.administrativeUnitId,
      locationUnitId: _hasLocationTree ? _selectedId(_Branch.national) : _existing?.locationUnitId,
      village: _village.text,
      clan: _clan.text,
      latitude: _gps?.latitude,
      longitude: _gps?.longitude,
      gpsAccuracy: _gps?.accuracy,
      status: _existing?.status,
    );
    try {
      if (_isEdit) {
        await repo.update(widget.uuid!, farm);
      } else {
        await repo.create(farm);
      }
      if (!mounted) return;
      showMessage(context, 'Farm saved on this device.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save: $e', error: true);
      }
    }
  }

  Widget _levelDropdown(_Branch branch, int i) {
    final level = _branches[branch]![i];
    return DropdownButtonFormField<int>(
      key: ValueKey('${branch.name}-$i-${level.options.first.id}'),
      value: level.selected?.id,
      isExpanded: true,
      decoration: InputDecoration(labelText: level.options.first.levelLabel),
      items: [for (final u in level.options) DropdownMenuItem(value: u.id, child: Text(u.name))],
      onChanged: (id) => _onUnitSelected(branch, i, level.options.where((u) => u.id == id).firstOrNull),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
    if (_existing != null && !_existing!.sync.canEditFromDevice) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit farm')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'This farm is managed by the office',
          message: 'It was registered at the office, so changes must be made there.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit farm' : 'Add farm')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_farmerName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Farmer: $_farmerName', style: Theme.of(context).textTheme.titleMedium),
            ),
          SectionCard(title: 'Farm', icon: Icons.landscape_outlined, children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Farm name *'),
              textCapitalization: TextCapitalization.words,
              validator: Validators.required('Farm name'),
            ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: _size,
                  decoration: const InputDecoration(labelText: 'Size *'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: Validators.positiveNumber('Size', max: 100000),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: [
                  for (final e in Farm.units.entries) ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {_unit},
                onSelectionChanged: (s) => setState(() => _unit = s.first),
              ),
            ]),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Location', icon: Icons.map_outlined, children: [
            if (_hasLocationTree) ...[
              DropdownButtonFormField<int>(
                value: _countyUnit?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'County *'),
                items: [for (final c in _counties) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (id) => _onCountySelected(_counties.where((c) => c.id == id).firstOrNull),
                validator: (id) => id == null ? 'County is required' : null,
              ),
              const SizedBox(height: 12),
              for (final branch in _Branch.values)
                if (_branches[branch]!.isNotEmpty) ...[
                  Text(branch.title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _branches[branch]!.length; i++) ...[
                    _levelDropdown(branch, i),
                    const SizedBox(height: 12),
                  ],
                ],
            ]
            else ...[
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _county.text),
                optionsBuilder: (v) => v.text.isEmpty
                    ? const Iterable<String>.empty()
                    : kenyaCounties.where((c) => c.toLowerCase().startsWith(v.text.toLowerCase())),
                onSelected: (v) => _county.text = v,
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'County *'),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (v) => _county.text = v,
                  validator: Validators.required('County'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subCounty,
                decoration: const InputDecoration(labelText: 'Sub-county'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ward,
                decoration: const InputDecoration(labelText: 'Ward'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _village,
              decoration: const InputDecoration(labelText: 'Village'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _clan,
              decoration: const InputDecoration(labelText: 'Clan'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            GpsCapture(
              label: 'Farm GPS point',
              initial: _gps,
              autoCapture: !_isEdit,
              onChanged: (fix) => setState(() => _gps = fix),
            ),
            const SizedBox(height: 4),
            Text('Stand inside the farm when capturing the point.', style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_isEdit ? 'Save changes' : 'Save farm'),
          ),
        ]),
      ),
    );
  }
}

enum _Branch {
  administrative('County government', 'SUB_COUNTY'),
  national('National government', 'LOCATION');

  const _Branch(this.title, this.firstLevel);

  final String title;
  final String firstLevel;
}

class _LocationLevel {
  const _LocationLevel(this.options, this.selected);

  static const none = _LocationLevel([], null);

  final List<AdminUnit> options;
  final AdminUnit? selected;
}

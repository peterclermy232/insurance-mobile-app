import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../farms/data/farm_repository.dart';
import '../../farms/models/farm.dart';
import '../../farms/screens/farm_list_screen.dart';
import '../data/inspection_repository.dart';
import '../models/inspection.dart';
import 'inspection_detail_screen.dart';

/// Create an inspection for a farm. Check-in, findings and check-out are
/// done on the inspection screen.
class InspectionFormScreen extends StatefulWidget {
  const InspectionFormScreen({super.key, this.farmUuid});

  final String? farmUuid;

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  Farm? _farm;
  String? _type;
  DateTime _date = DateTime.now();
  TimeOfDay? _time = TimeOfDay.now();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.farmUuid != null) _farm = await context.read<FarmRepository>().get(widget.farmUuid!);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chooseFarm() async {
    final farm = await pickFarm(context, title: 'Farm to inspect');
    if (farm != null) setState(() => _farm = farm);
  }

  Future<void> _save() async {
    if (_farm == null || _type == null) {
      showMessage(context, _farm == null ? 'Choose the farm to inspect.' : 'Choose the inspection type.', error: true);
      return;
    }
    setState(() => _saving = true);
    final t = _time;
    final uuid = await context.read<InspectionRepository>().create(Inspection(
          farmUuid: _farm!.uuid,
          type: _type!,
          status: 'SCHEDULED',
          scheduledDate: Fmt.isoDate(_date),
          scheduledTime: t == null
              ? null
              : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
        ));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InspectionDetailScreen(uuid: uuid)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
    return Scaffold(
      appBar: AppBar(title: const Text('New inspection')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(title: 'Farm', icon: Icons.landscape_outlined, children: [
          if (_farm == null)
            OutlinedButton.icon(onPressed: _chooseFarm, icon: const Icon(Icons.search), label: const Text('Choose farm'))
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_farm!.name),
              subtitle: Text('${_farm!.farmerName ?? ''}  |  ${_farm!.locationLabel}'),
              trailing: widget.farmUuid == null ? TextButton(onPressed: _chooseFarm, child: const Text('Change')) : null,
            ),
        ]),
        const SizedBox(height: 12),
        SectionCard(title: 'Inspection', icon: Icons.fact_check_outlined, children: [
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Type *'),
            items: [
              for (final e in Inspection.types.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _date = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child: Text(Fmt.date(_date)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
                  if (t != null) setState(() => _time = t);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Time'),
                  child: Text(_time == null ? '-' : _time!.format(context)),
                ),
              ),
            ),
          ]),
        ]),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Create inspection'),
        ),
      ]),
    );
  }
}

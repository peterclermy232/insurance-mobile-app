import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/location/location_service.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/photo_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_helpers.dart';
import '../../../core/widgets/gps_capture.dart';
import '../data/farmer_repository.dart';
import '../models/farmer.dart';
import '../widgets/farmer_avatar.dart';
import 'farmer_detail_screen.dart';

/// Register a farmer (uuid == null) or edit one. Saved on the device first.
class FarmerFormScreen extends StatefulWidget {
  const FarmerFormScreen({super.key, this.uuid});

  final String? uuid;

  @override
  State<FarmerFormScreen> createState() => _FarmerFormScreenState();
}

class _FarmerFormScreenState extends State<FarmerFormScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _idNumber = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  static const _defaultCategories = ['Smallholder', 'Medium-scale', 'Large-scale', 'Cooperative member'];
  List<String> _categories = _defaultCategories;
  static const _genders = {'M': 'Male', 'F': 'Female', 'O': 'Other'};

  String? _gender;
  String? _category;
  DateTime? _dob;
  GeoFix? _gps;
  CapturedPhoto? _newPhoto;
  String? _existingPhotoPath;
  String? _existingPhotoUrl;
  List<NextOfKin> _kin = [];
  List<BankAccount> _banks = [];

  bool _loading = true;
  bool _saving = false;
  Farmer? _existing;

  bool get _isEdit => widget.uuid != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_isEdit) {
      final farmer = await context.read<FarmerRepository>().get(widget.uuid!);
      if (farmer != null) {
        _existing = farmer;
        _firstName.text = farmer.firstName;
        _lastName.text = farmer.lastName;
        _idNumber.text = farmer.idNumber;
        _phone.text = farmer.phoneNumber;
        _email.text = farmer.email ?? '';
        _gender = switch (farmer.gender?.toUpperCase()) {
          'M' || 'MALE' => 'M',
          'F' || 'FEMALE' => 'F',
          'O' || 'OTHER' => 'O',
          _ => null,
        };
        // Keep a category set at the office even if it isn't one of ours.
        final category = farmer.category;
        if (category != null && category.isNotEmpty && !_categories.contains(category)) {
          _categories = [..._categories, category];
        }
        _category = category?.isEmpty ?? true ? null : category;
        _dob = farmer.dateOfBirth == null ? null : DateTime.tryParse(farmer.dateOfBirth!);
        if (farmer.latitude != null && farmer.longitude != null) {
          _gps = GeoFix(latitude: farmer.latitude!, longitude: farmer.longitude!, accuracy: farmer.gpsAccuracy);
        }
        _kin = [...farmer.nextOfKin];
        _banks = [...farmer.bankAccounts];
        _existingPhotoPath = farmer.localPhotoPath;
        _existingPhotoUrl = farmer.photoUrl;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _idNumber, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 35),
      firstDate: DateTime(now.year - 110),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await context.read<PhotoService>().capture(tagLocation: false);
      if (photo != null) setState(() => _newPhoto = photo);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not take photo: $e', error: true);
    }
  }

  Future<void> _editKin([int? index]) async {
    final current = index == null ? null : _kin[index];
    final values = await showFieldsDialog(context, title: index == null ? 'Add next of kin' : 'Edit next of kin', fields: [
      DialogField('name', 'Full name', validator: Validators.required('Name'), initial: current?.name ?? ''),
      DialogField('relationship', 'Relationship (e.g. Spouse)',
          validator: Validators.required('Relationship'), initial: current?.relationship ?? ''),
      DialogField('phone', 'Phone number',
          validator: (v) => Validators.phone(v), keyboardType: TextInputType.phone, initial: current?.phoneNumber ?? ''),
    ]);
    if (values == null) return;
    final kin = NextOfKin(name: values['name']!, relationship: values['relationship']!, phoneNumber: values['phone']!);
    setState(() => index == null ? _kin.add(kin) : _kin[index] = kin);
  }

  Future<void> _editBank([int? index]) async {
    final current = index == null ? null : _banks[index];
    final values = await showFieldsDialog(context, title: index == null ? 'Add bank account' : 'Edit bank account', fields: [
      DialogField('bank', 'Bank name', validator: Validators.required('Bank name'), initial: current?.bankName ?? ''),
      DialogField('number', 'Account number',
          validator: Validators.required('Account number'),
          keyboardType: TextInputType.number,
          initial: current?.accountNumber ?? ''),
      DialogField('name', 'Account name', validator: Validators.required('Account name'), initial: current?.accountName ?? ''),
    ]);
    if (values == null) return;
    final account =
        BankAccount(bankName: values['bank']!, accountNumber: values['number']!, accountName: values['name']!);
    setState(() => index == null ? _banks.add(account) : _banks[index] = account);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      showMessage(context, 'Please correct the highlighted fields.', error: true);
      return;
    }
    final repo = context.read<FarmerRepository>();
    final media = context.read<MediaRepository>();

    final clash = await repo.findByIdNumber(_idNumber.text, exceptUuid: widget.uuid);
    if (!mounted) return;
    if (clash != null) {
      showMessage(context, 'ID ${_idNumber.text.trim()} is already registered on this device for ${clash.fullName}.',
          error: true);
      return;
    }
    if (_gps == null) {
      final proceed = await confirm(context,
          title: 'No GPS location',
          message: 'The registration location has not been captured. Save without it?',
          confirmLabel: 'Save anyway');
      if (!proceed || !mounted) return;
    }

    setState(() => _saving = true);
    final farmer = Farmer(
      firstName: _firstName.text,
      lastName: _lastName.text,
      idNumber: _idNumber.text,
      phoneNumber: _phone.text.replaceAll(RegExp(r'[\s-]'), ''),
      email: _email.text,
      gender: _gender,
      dateOfBirth: _dob == null ? null : Fmt.isoDate(_dob!),
      category: _category,
      latitude: _gps?.latitude,
      longitude: _gps?.longitude,
      gpsAccuracy: _gps?.accuracy,
      nextOfKin: _kin,
      bankAccounts: _banks,
    );
    try {
      final String uuid;
      if (_isEdit) {
        uuid = widget.uuid!;
        await repo.update(uuid, farmer);
      } else {
        uuid = await repo.create(farmer);
      }
      if (_newPhoto != null) await media.setProfilePhoto(uuid, _newPhoto!);
      if (!mounted) return;
      showMessage(context, _isEdit ? 'Changes saved. They will upload at the next sync.' : 'Farmer saved on this device.');
      if (_isEdit) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context)
            .pushReplacement(MaterialPageRoute(builder: (_) => FarmerDetailScreen(uuid: uuid)));
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
    if (_isEdit && _existing != null && !_existing!.sync.canEditFromDevice) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit farmer')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'This farmer is managed by the office',
          message: 'It was registered at the office, so changes must be made there.',
        ),
      );
    }
    final initials = '${_firstName.text.isNotEmpty ? _firstName.text[0] : ''}'
            '${_lastName.text.isNotEmpty ? _lastName.text[0] : ''}'
        .toUpperCase();

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit farmer' : 'Register farmer')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: Column(children: [
              FarmerAvatar(
                initials: initials.isEmpty ? '?' : initials,
                localPath: _newPhoto?.path ?? _existingPhotoPath,
                url: _existingPhotoUrl,
                radius: 44,
              ),
              TextButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(_newPhoto == null && _existingPhotoPath == null && _existingPhotoUrl == null
                    ? 'Take profile photo'
                    : 'Retake photo'),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          SectionCard(title: 'Personal details', icon: Icons.badge_outlined, children: [
            TextFormField(
              controller: _firstName,
              decoration: const InputDecoration(labelText: 'First name *'),
              textCapitalization: TextCapitalization.words,
              validator: Validators.required('First name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastName,
              decoration: const InputDecoration(labelText: 'Last name *'),
              textCapitalization: TextCapitalization.words,
              validator: Validators.required('Last name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _idNumber,
              decoration: const InputDecoration(labelText: 'National ID number *'),
              keyboardType: TextInputType.number,
              validator: Validators.nationalId,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: const InputDecoration(labelText: 'Gender *'),
              items: [for (final e in _genders.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _gender = v),
              validator: (v) => v == null ? 'Select gender' : null,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDob,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date of birth',
                  suffixIcon: _dob == null
                      ? const Icon(Icons.calendar_today_outlined)
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _dob = null),
                        ),
                ),
                child: Text(_dob == null ? 'Not set' : Fmt.date(_dob)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Farmer category (optional)'),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('Not specified')),
                for (final c in _categories) DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Contact', icon: Icons.phone_outlined, children: [
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone number *', hintText: '0712345678'),
              keyboardType: TextInputType.phone,
              validator: (v) => Validators.phone(v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
            ),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Registration location', icon: Icons.place_outlined, children: [
            GpsCapture(
              label: 'GPS position',
              initial: _gps,
              autoCapture: !_isEdit,
              onChanged: (fix) => setState(() => _gps = fix),
            ),
          ]),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Next of kin',
            icon: Icons.family_restroom,
            trailing: TextButton.icon(onPressed: _editKin, icon: const Icon(Icons.add), label: const Text('Add')),
            children: [
              if (_kin.isEmpty) const Text('None added'),
              for (var i = 0; i < _kin.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_kin[i].name),
                  subtitle: Text('${_kin[i].relationship}  |  ${_kin[i].phoneNumber}'),
                  onTap: () => _editKin(i),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _kin.removeAt(i)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Bank accounts',
            icon: Icons.account_balance_outlined,
            trailing: TextButton.icon(onPressed: _editBank, icon: const Icon(Icons.add), label: const Text('Add')),
            children: [
              if (_banks.isEmpty) const Text('None added'),
              for (var i = 0; i < _banks.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_banks[i].bankName),
                  subtitle: Text('${_banks[i].accountNumber}  |  ${_banks[i].accountName}'),
                  onTap: () => _editBank(i),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _banks.removeAt(i)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_isEdit ? 'Save changes' : 'Save farmer'),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

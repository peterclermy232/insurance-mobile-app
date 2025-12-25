import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../models/farmer_model.dart';
import '../models/organisation_model.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';

class FarmerFormScreen extends StatefulWidget {
  const FarmerFormScreen({Key? key}) : super(key: key);

  @override
  State<FarmerFormScreen> createState() => _FarmerFormScreenState();
}

class _FarmerFormScreenState extends State<FarmerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  List<Organisation> _organisations = [];
  Organisation? _selectedOrganisation;
  bool _isLoadingOrganisations = true;

  String? _selectedGender;
  Position? _currentPosition;
  File? _photoFile;

  bool _isLoading = false;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    _loadOrganisations();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _idNumberController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ================= LOAD ORGANISATIONS =================
  Future<void> _loadOrganisations() async {
    setState(() => _isLoadingOrganisations = true);
    try {
      final data = await ApiClient.instance.getOrganisations();
      _organisations = data
          .map((e) => Organisation.fromJson(e))
          .where((o) => o.status == 'ACTIVE')
          .toList();

      final userOrgId = await ApiClient.instance.getOrganisationId();
      if (userOrgId != null) {
        final id = int.tryParse(userOrgId);
        if (id != null) {
          _selectedOrganisation =
              _organisations.firstWhere((o) => o.organisationId == id);
        }
      }
    } catch (e) {
      _showSnack('Failed to load organisations: $e', Colors.red);
    } finally {
      setState(() => _isLoadingOrganisations = false);
    }
  }

  // ================= PHOTO =================
  Future<void> _takePhoto() async {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // ✅ FIX
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                final file = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 800,
                  maxHeight: 800,
                  imageQuality: 75,
                );
                if (file != null) {
                  setState(() => _photoFile = File(file.path));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final file = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 800,
                  maxHeight: 800,
                  imageQuality: 75,
                );
                if (file != null) {
                  setState(() => _photoFile = File(file.path));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ================= LOCATION =================
  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw 'Location services disabled';

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Location permission permanently denied';
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() => _currentPosition = pos);
      _showSnack('Location captured', Colors.green);
    } catch (e) {
      _showSnack('Location error: $e', Colors.red);
    } finally {
      setState(() => _isGettingLocation = false);
    }
  }

  // ================= SAVE FARMER =================
  Future<void> _saveFarmer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOrganisation == null) {
      _showSnack('Please select an organisation', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = await AppDatabase.instance.database;

      final farmer = Farmer(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        idNumber: _idNumberController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        gender: _selectedGender,
        registration_latitude: _currentPosition?.latitude,
        registration_longitude: _currentPosition?.longitude,
        photoPath: _photoFile?.path,
        organisationId: _selectedOrganisation!.organisationId,
        organisationName: _selectedOrganisation!.organisationName,
        syncStatus: 'pending',
      );

      final id = await db.insert('farmers', farmer.toMap());

      await db.insert('sync_queue', {
        'entity_type': 'farmer',
        'entity_id': id,
        'operation': 'create',
        'priority': 3,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      if (_photoFile != null) {
        await db.insert('media_queue', {
          'file_path': _photoFile!.path,
          'entity_type': 'farmer',
          'entity_id': id,
          'sync_status': 'pending',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }

      if (mounted) {
        Navigator.pop(context, true);
        _showSnack('Farmer saved (sync pending)', Colors.green);
      }
    } catch (e) {
      _showSnack('Save failed: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Farmer'),
        backgroundColor: Colors.green,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPhotoSection(),
                const SizedBox(height: 24),
                _buildOrganisationSection(),
                const SizedBox(height: 24),
                _buildPersonalInfo(),
                const SizedBox(height: 24),
                _buildContactInfo(),
                const SizedBox(height: 24),
                _buildLocationSection(),
                const SizedBox(height: 32),
                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= WIDGETS =================
  Widget _buildPhotoSection() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min, // ✅ FIX
        children: [
          _photoFile != null
              ? Image.file(_photoFile!, height: 200, fit: BoxFit.cover)
              : Container(
            height: 200,
            color: Colors.grey[200],
            child: const Icon(Icons.person, size: 80),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.camera_alt),
            label:
            Text(_photoFile == null ? 'Take Photo' : 'Retake Photo'),
          )
        ],
      ),
    ),
  );

  Widget _buildLocationSection() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min, // ✅ FIX
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Location',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _currentPosition == null
              ? const Text('No location captured')
              : Text(
              '${_currentPosition!.latitude}, ${_currentPosition!.longitude}'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isGettingLocation ? null : _getCurrentLocation,
            icon: const Icon(Icons.my_location),
            label: const Text('Capture Location'),
          ),
        ],
      ),
    ),
  );

  Widget _buildOrganisationSection() => _isLoadingOrganisations
      ? const Center(child: CircularProgressIndicator())
      : DropdownButtonFormField<Organisation>(
    value: _selectedOrganisation,
    decoration:
    const InputDecoration(labelText: 'Organisation *'),
    items: _organisations
        .map(
          (o) => DropdownMenuItem(
        value: o,
        child: Text(o.organisationName),
      ),
    )
        .toList(),
    onChanged: (v) => setState(() => _selectedOrganisation = v),
    validator: (v) => v == null ? 'Required' : null,
  );

  Widget _buildPersonalInfo() => Column(children: [
    TextFormField(
      controller: _firstNameController,
      decoration: const InputDecoration(labelText: 'First Name *'),
      validator: (v) => v!.isEmpty ? 'Required' : null,
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _lastNameController,
      decoration: const InputDecoration(labelText: 'Last Name *'),
      validator: (v) => v!.isEmpty ? 'Required' : null,
    ),
  ]);

  Widget _buildContactInfo() => Column(children: [
    TextFormField(
      controller: _idNumberController,
      decoration: const InputDecoration(labelText: 'ID Number *'),
      validator: (v) => v!.isEmpty ? 'Required' : null,
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _phoneController,
      decoration: const InputDecoration(labelText: 'Phone Number *'),
      validator: (v) => v!.isEmpty ? 'Required' : null,
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _emailController,
      decoration:
      const InputDecoration(labelText: 'Email (optional)'),
    ),
  ]);

  Widget _buildSaveButton() => ElevatedButton(
    onPressed: _saveFarmer,
    child: const Text('SAVE FARMER'),
  );

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}

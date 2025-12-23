import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';


class NewClaimScreen extends StatefulWidget {
  const NewClaimScreen({Key? key}) : super(key: key);

  @override
  State<NewClaimScreen> createState() => _NewClaimScreenState();
}

class _NewClaimScreenState extends State<NewClaimScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  List<Map<String, dynamic>> _farmers = [];
  List<String> _photosPaths = [];
  int? _selectedFarmerId;
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadFarmers();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadFarmers() async {
    final db = await AppDatabase.instance.database;
    final farmers = await db.query(
      'farmers',
      where: 'sync_status = ?',
      whereArgs: ['synced'],
      orderBy: 'first_name ASC',
    );

    setState(() => _farmers = farmers);
  }

  Future<void> _captureLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location captured successfully')),
        );
      }
    } catch (e) {
      setState(() => _isLoadingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        setState(() {
          _photosPaths.add(photo.path);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Photo added (${_photosPaths.length} total)')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to take photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveClaim() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFarmerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a farmer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = await AppDatabase.instance.database;

      final lossDetails = {
        'assessor_notes': _notesController.text,
        'photos_count': _photosPaths.length,
        'assessment_date': DateTime.now().toIso8601String(),
      };

      final claimData = {
        'farmer_id': _selectedFarmerId,
        'quotation_id': 1, // TODO: Link to actual quotation
        'estimated_loss_amount': double.parse(_amountController.text),
        'loss_details': jsonEncode(lossDetails),
        'photos': jsonEncode(_photosPaths),
        'assessor_notes': _notesController.text,
        'latitude': _currentPosition?.latitude,
        'longitude': _currentPosition?.longitude,
        'sync_status': 'pending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

      final claimId = await db.insert('claims', claimData);

      // Queue photos for upload
      for (String photoPath in _photosPaths) {
        await db.insert('media_queue', {
          'file_path': photoPath,
          'entity_type': 'claim',
          'entity_id': claimId,
          'sync_status': 'pending',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Claim saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save claim: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photosPaths.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Claim Assessment'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Farmer Selection
            DropdownButtonFormField<int>(
              value: _selectedFarmerId,
              decoration: const InputDecoration(
                labelText: 'Select Farmer',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              items: _farmers.map((farmer) {
                return DropdownMenuItem<int>(
                  value: farmer['id'] as int,
                  child: Text(
                    '${farmer['first_name']} ${farmer['last_name']}',
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedFarmerId = value);
              },
              validator: (value) {
                if (value == null) return 'Please select a farmer';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Estimated Loss Amount
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Estimated Loss Amount (KES)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter loss amount';
                }
                if (double.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }
                if (double.parse(value) <= 0) {
                  return 'Amount must be greater than zero';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Assessment Notes
            TextFormField(
              controller: _notesController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Assessment Notes',
                border: OutlineInputBorder(),
                hintText: 'Describe the damage and circumstances...',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter assessment notes';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Location Capture
            Card(
              child: ListTile(
                leading: Icon(
                  _currentPosition != null
                      ? Icons.location_on
                      : Icons.location_off,
                  color: _currentPosition != null ? Colors.green : Colors.grey,
                ),
                title: Text(
                  _currentPosition != null
                      ? 'Location Captured'
                      : 'No Location',
                ),
                subtitle: _currentPosition != null
                    ? Text(
                  'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}\n'
                      'Lon: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                )
                    : const Text('Tap to capture current location'),
                trailing: _isLoadingLocation
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.chevron_right),
                onTap: _isLoadingLocation ? null : _captureLocation,
              ),
            ),
            const SizedBox(height: 16),

            // Photos Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Photos (${_photosPaths.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _takePhoto,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Take Photo'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_photosPaths.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No photos added yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _photosPaths.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_photosPaths[index]),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removePhoto(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            ElevatedButton(
              onPressed: _isSaving ? null : _saveClaim,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
              ),
              child: _isSaving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Text(
                'SAVE CLAIM',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../services/location_service.dart';

class EnhancedNewClaimScreen extends StatefulWidget {
  const EnhancedNewClaimScreen({Key? key}) : super(key: key);

  @override
  State<EnhancedNewClaimScreen> createState() => _EnhancedNewClaimScreenState();
}

class _EnhancedNewClaimScreenState extends State<EnhancedNewClaimScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _locationService = LocationService();

  List<Map<String, dynamic>> _farmers = [];
  List<Map<String, dynamic>> _quotations = [];
  List<File> _photos = [];

  int? _selectedFarmerId;
  int? _selectedQuotationId;
  Position? _currentPosition;

  bool _isLoadingFarmers = true;
  bool _isLoadingQuotations = false;
  bool _isGettingLocation = false;
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

  // ============ DATA LOADING ============
  Future<void> _loadFarmers() async {
    setState(() => _isLoadingFarmers = true);
    try {
      final db = await AppDatabase.instance.database;

      // Load synced farmers from local DB
      final farmers = await db.query(
        'farmers',
        where: 'sync_status = ? AND status = ?',
        whereArgs: ['synced', 'ACTIVE'],
        orderBy: 'first_name ASC',
      );

      setState(() {
        _farmers = farmers;
        _isLoadingFarmers = false;
      });

      if (_farmers.isEmpty) {
        _showSnack('No synced farmers found. Please sync first.', Colors.orange);
      } else {
        print('✅ Loaded ${_farmers.length} farmers');
      }
    } catch (e) {
      setState(() => _isLoadingFarmers = false);
      _showSnack('Error loading farmers: $e', Colors.red);
      print('❌ Error loading farmers: $e');
    }
  }

  Future<void> _loadQuotations(int farmerId) async {
    setState(() {
      _isLoadingQuotations = true;
      _quotations = [];
      _selectedQuotationId = null;
    });

    try {
      print('🔍 Loading quotations for farmer ID: $farmerId');

      // Get farmer details
      final db = await AppDatabase.instance.database;
      final farmerResult = await db.query(
        'farmers',
        where: 'id = ?',
        whereArgs: [farmerId],
      );

      if (farmerResult.isEmpty) {
        throw Exception('Farmer not found in local database');
      }

      final farmer = farmerResult.first;
      final farmerServerId = farmer['server_id'];

      print('   Local Farmer ID: $farmerId');
      print('   Server Farmer ID: $farmerServerId');

      // First check if we need to sync quotations from server
      final isOnline = await ApiClient.instance.isOnline();

      if (isOnline && farmerServerId != null) {
        try {
          print('📡 Fetching quotations from server for farmer $farmerServerId...');

          final response = await ApiClient.instance.get(
            '/quotations/',
            queryParameters: {'farmer_id': farmerServerId},
          );

          // Handle different response formats
          final List<dynamic> serverQuotations = response is List
              ? response
              : (response['results'] ?? response['data'] ?? []);

          print('   Server returned ${serverQuotations.length} quotations');
          print('   Raw response: $response');

          // Save to local database
          for (var quot in serverQuotations) {
            try {
              final quotationData = {
                'server_id': quot['quotation_id'] ?? quot['id'],
                'farmer_id': farmerId, // Use LOCAL farmer ID
                'farm_id': quot['farm'] ?? quot['farm_id'],
                'premium_amount': quot['premium_amount']?.toString() ?? '0',
                'sum_insured': quot['sum_insured']?.toString() ?? '0',
                'status': quot['status'] ?? 'UNKNOWN',
                'sync_status': 'synced',
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'updated_at': DateTime.now().millisecondsSinceEpoch,
              };

              // Check if quotation already exists
              final existing = await db.query(
                'quotations',
                where: 'server_id = ?',
                whereArgs: [quotationData['server_id']],
              );

              if (existing.isEmpty) {
                await db.insert(
                  'quotations',
                  quotationData,
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                print('   ✅ Saved quotation ${quotationData['server_id']}');
              } else {
                await db.update(
                  'quotations',
                  quotationData,
                  where: 'server_id = ?',
                  whereArgs: [quotationData['server_id']],
                );
                print('   ✅ Updated quotation ${quotationData['server_id']}');
              }
            } catch (e) {
              print('   ⚠️ Error saving quotation: $e');
            }
          }

          print('✅ Fetched and saved ${serverQuotations.length} quotations from server');
        } catch (e) {
          print('⚠️ Could not fetch quotations from server: $e');
          // Continue to load from local DB
        }
      } else {
        print('📴 Offline or farmer not synced - loading from local DB only');
      }

      // Load from local database
      final quotations = await db.query(
        'quotations',
        where: 'farmer_id = ? AND (status = ? OR status = ?)',
        whereArgs: [farmerId, 'WRITTEN', 'PAID'],
        orderBy: 'created_at DESC',
      );

      print('📊 Found ${quotations.length} local quotations');

      for (var q in quotations) {
        print('   - Quotation ${q['server_id']}: ${q['status']} (Sum: ${q['sum_insured']})');
      }

      setState(() {
        _quotations = quotations;
        _isLoadingQuotations = false;

        // Auto-select first quotation if available
        if (quotations.isNotEmpty) {
          _selectedQuotationId = quotations.first['server_id'] as int?;
          print('✅ Auto-selected quotation: $_selectedQuotationId');
        }
      });

      if (_quotations.isEmpty) {
        _showSnack(
          'No WRITTEN or PAID policies found for this farmer',
          Colors.orange,
        );
        print('⚠️ Farmer $farmerId has no active policies. They need to create a policy first.');
      } else {
        _showSnack(
          'Loaded ${_quotations.length} ${_quotations.length == 1 ? "policy" : "policies"}',
          Colors.green,
        );
      }
    } catch (e) {
      setState(() => _isLoadingQuotations = false);
      _showSnack('Error loading quotations: $e', Colors.red);
      print('❌ Error loading quotations: $e');
    }
  }

  // ============ LOCATION ============
  Future<void> _captureLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      final position = await _locationService.getCurrentPosition(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() => _currentPosition = position);
      _showSnack('Location captured: ${_locationService.getAccuracyDescription(position.accuracy)}', Colors.green);
    } catch (e) {
      _showSnack('Location error: $e', Colors.red);
    } finally {
      setState(() => _isGettingLocation = false);
    }
  }

  // ============ PHOTOS ============
  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        setState(() => _photos.add(File(photo.path)));
        _showSnack('Photo added (${_photos.length} total)', Colors.green);
      }
    } catch (e) {
      _showSnack('Camera error: $e', Colors.red);
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  // ============ SAVE CLAIM ============
  Future<void> _saveClaim() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedFarmerId == null) {
      _showSnack('Please select a farmer', Colors.red);
      return;
    }

    if (_selectedQuotationId == null) {
      _showSnack('Please select a quotation/policy', Colors.red);
      return;
    }

    if (_photos.isEmpty) {
      final confirm = await _showConfirmDialog(
        'No Photos',
        'You haven\'t added any photos. Continue anyway?',
      );
      if (confirm != true) return;
    }

    setState(() => _isSaving = true);

    try {
      final db = await AppDatabase.instance.database;

      // Get farmer's server_id
      final farmer = await db.query(
        'farmers',
        where: 'id = ?',
        whereArgs: [_selectedFarmerId],
      );

      if (farmer.isEmpty || farmer.first['server_id'] == null) {
        throw Exception('Farmer not synced to server. Please sync farmers first.');
      }

      final farmerServerId = farmer.first['server_id'] as int;

      // Get quotation details
      final quotation = await db.query(
        'quotations',
        where: 'server_id = ?',
        whereArgs: [_selectedQuotationId],
      );

      if (quotation.isEmpty) {
        throw Exception('Selected quotation not found in local database');
      }

      final quotServerId = quotation.first['server_id'] as int;

      // Build loss details
      final lossDetails = {
        'assessor_notes': _notesController.text,
        'photos_count': _photos.length,
        'assessment_date': DateTime.now().toIso8601String(),
        'latitude': _currentPosition?.latitude,
        'longitude': _currentPosition?.longitude,
      };

      // ✅ FIX: Send loss_details as JSON string
      final claimData = {
        'farmer': farmerServerId,
        'quotation': quotServerId,
        'estimated_loss_amount': double.parse(_amountController.text),
        'loss_details': jsonEncode(lossDetails), // ← Changed to JSON string
        'status': 'OPEN',
      };

      print('📤 Sending claim to API:');
      print('   Farmer ID: $farmerServerId');
      print('   Quotation ID: $quotServerId');
      print('   Amount: ${claimData['estimated_loss_amount']}');
      print('   Loss Details (JSON): ${claimData['loss_details']}');

      // Check online status
      if (!await ApiClient.instance.isOnline()) {
        throw Exception('No internet connection. Please connect and try again.');
      }

      // Save to server first
      final response = await ApiClient.instance.createClaim(claimData);

      print('✅ Claim created on server:');
      print('   Claim ID: ${response['claim_id']}');
      print('   Claim Number: ${response['claim_number']}');

      // Upload photos if any
      if (_photos.isNotEmpty) {
        await _uploadPhotos(response['claim_id']);
      }

      // Save to local DB
      final claimId = await db.insert('claims', {
        'farmer_id': _selectedFarmerId,
        'server_id': response['claim_id'],
        'claim_number': response['claim_number'],
        'quotation_id': quotServerId,
        'estimated_loss_amount': double.parse(_amountController.text),
        'loss_details': jsonEncode(lossDetails),
        'assessor_notes': _notesController.text,
        'photos': jsonEncode(_photos.map((f) => f.path).toList()),
        'latitude': _currentPosition?.latitude,
        'longitude': _currentPosition?.longitude,
        'sync_status': 'synced',
        'status': 'OPEN',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      print('✅ Claim saved locally with ID: $claimId');

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Claim created: ${response['claim_number']}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Error creating claim: $e');
      String errorMessage = 'Failed to create claim';

      if (e.toString().contains('Farmer not synced')) {
        errorMessage = 'Farmer not synced. Please sync data first.';
      } else if (e.toString().contains('No internet')) {
        errorMessage = 'No internet connection. Connect and try again.';
      } else if (e.toString().contains('500')) {
        errorMessage = 'Server error. Contact administrator.';
      } else if (e.toString().contains('400')) {
        // ✅ Enhanced error message for debugging
        errorMessage = 'Invalid data format. Check: $e';
        print('🔍 Full error details: $e');
      }

      _showSnack(errorMessage, Colors.red);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _uploadPhotos(int claimId) async {
    for (var photo in _photos) {
      try {
        await ApiClient.instance.uploadImage(photo.path, 'photo');
        print('✅ Uploaded photo: ${photo.path}');
      } catch (e) {
        print('❌ Failed to upload photo: $e');
      }
    }
  }

  // ============ UI HELPERS ============
  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
  }

  // ============ BUILD UI ============
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Claim Assessment'),
        backgroundColor: Colors.green,
      ),
      body: _isLoadingFarmers
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildFarmerSection(),
            const SizedBox(height: 16),
            _buildQuotationSection(),
            const SizedBox(height: 16),
            _buildAmountSection(),
            const SizedBox(height: 16),
            _buildNotesSection(),
            const SizedBox(height: 16),
            _buildLocationSection(),
            const SizedBox(height: 16),
            _buildPhotosSection(),
            const SizedBox(height: 32),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildFarmerSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Farmer Selection',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_farmers.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Column(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 32),
                    const SizedBox(height: 8),
                    const Text(
                      'No farmers available',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Please sync farmers from the main screen first',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<int>(
                value: _selectedFarmerId,
                decoration: const InputDecoration(
                  labelText: 'Select Farmer *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                  helperText: 'Choose the farmer making the claim',
                ),
                items: _farmers.map((farmer) {
                  final firstName = farmer['first_name'] ?? '';
                  final lastName = farmer['last_name'] ?? '';
                  final serverId = farmer['server_id'];

                  return DropdownMenuItem<int>(
                    value: farmer['id'] as int,
                    child: Text(
                      '$firstName $lastName ${serverId != null ? "✓" : "⚠"}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  print('🔄 Farmer selected: $value');
                  setState(() {
                    _selectedFarmerId = value;
                    _selectedQuotationId = null;
                    _quotations = [];
                  });
                  if (value != null) {
                    _loadQuotations(value);
                  }
                },
                validator: (value) => value == null ? 'Please select a farmer' : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotationSection() {
    if (_selectedFarmerId == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                'Select a farmer first',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingQuotations) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading policies...'),
            ],
          ),
        ),
      );
    }

    if (_quotations.isEmpty) {
      return Card(
        color: Colors.orange[50],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.warning_amber, size: 48, color: Colors.orange[700]),
              const SizedBox(height: 12),
              Text(
                'No Active Policies Found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[900],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This farmer needs a WRITTEN or PAID policy before creating a claim.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange[800]),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  // Refresh quotations
                  if (_selectedFarmerId != null) {
                    _loadQuotations(_selectedFarmerId!);
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.policy, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text(
                  'Select Policy',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _selectedQuotationId,
              decoration: const InputDecoration(
                labelText: 'Policy/Quotation *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
                helperText: 'Select the policy to claim against',
              ),
              items: _quotations.map((quot) {
                final sumInsured = quot['sum_insured'];
                final premiumAmount = quot['premium_amount'];
                final status = quot['status'] ?? 'UNKNOWN';

                // Convert to double if stored as string
                double sum = 0.0;
                double premium = 0.0;

                if (sumInsured is String) {
                  sum = double.tryParse(sumInsured) ?? 0.0;
                } else if (sumInsured is num) {
                  sum = sumInsured.toDouble();
                }

                if (premiumAmount is String) {
                  premium = double.tryParse(premiumAmount) ?? 0.0;
                } else if (premiumAmount is num) {
                  premium = premiumAmount.toDouble();
                }

                return DropdownMenuItem<int>(
                  value: quot['server_id'] as int? ?? quot['id'] as int,
                  child: Text(
                    'KES ${sum.toStringAsFixed(0)} - $status',
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedQuotationId = value);
              },
              validator: (value) => value == null ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Found ${_quotations.length} active ${_quotations.length == 1 ? "policy" : "policies"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Estimated Loss Amount (KES) *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.attach_money),
            helperText: 'Enter the estimated value of the loss',
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
      ),
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          controller: _notesController,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Assessment Notes *',
            border: OutlineInputBorder(),
            hintText: 'Describe the damage, cause, and any relevant details...',
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter assessment notes';
            }
            return null;
          },
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Card(
      child: ListTile(
        leading: Icon(
          _currentPosition != null ? Icons.location_on : Icons.location_off,
          color: _currentPosition != null ? Colors.green : Colors.grey,
        ),
        title: Text(
          _currentPosition != null ? 'Location Captured' : 'No Location',
        ),
        subtitle: _currentPosition != null
            ? Text(_locationService.formatPosition(_currentPosition!))
            : const Text('Tap to capture current location'),
        trailing: _isGettingLocation
            ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Icon(Icons.chevron_right),
        onTap: _isGettingLocation ? null : _captureLocation,
      ),
    );
  }

  Widget _buildPhotosSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Evidence Photos (${_photos.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_photos.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.photo_camera, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No photos added yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _photos.length,
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _photos[index],
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
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving ? null : _saveClaim,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: Colors.green,
        disabledBackgroundColor: Colors.grey,
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
        'SUBMIT CLAIM',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
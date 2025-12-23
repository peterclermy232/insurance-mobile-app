import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import '../../../core/database/app_database.dart';


class ClaimDetailScreen extends StatefulWidget {
  final int claimId;

  const ClaimDetailScreen({Key? key, required this.claimId}) : super(key: key);

  @override
  State<ClaimDetailScreen> createState() => _ClaimDetailScreenState();
}

class _ClaimDetailScreenState extends State<ClaimDetailScreen> {
  Map<String, dynamic>? _claim;
  Map<String, dynamic>? _farmer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClaimDetails();
  }

  Future<void> _loadClaimDetails() async {
    setState(() => _isLoading = true);

    try {
      final db = await AppDatabase.instance.database;

      final claims = await db.query(
        'claims',
        where: 'id = ?',
        whereArgs: [widget.claimId],
      );

      if (claims.isEmpty) {
        throw Exception('Claim not found');
      }

      final claim = claims.first;

      final farmers = await db.query(
        'farmers',
        where: 'id = ?',
        whereArgs: [claim['farmer_id']],
      );

      setState(() {
        _claim = claim;
        _farmer = farmers.isNotEmpty ? farmers.first : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load claim: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'synced':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('MMM dd, yyyy HH:mm').format(date);
  }

  Widget _buildInfoCard(String title, String value, {IconData? icon}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.grey[600]),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Claim Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_claim == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Claim Details')),
        body: const Center(child: Text('Claim not found')),
      );
    }

    final syncStatus = _claim!['sync_status'] ?? 'pending';
    final photosPaths = _claim!['photos'] != null
        ? List<String>.from(jsonDecode(_claim!['photos']))
        : <String>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Claim Details'),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getStatusColor(syncStatus),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              syncStatus.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Farmer Information
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Farmer Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  if (_farmer != null) ...[
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person),
                      ),
                      title: Text(
                        '${_farmer!['first_name']} ${_farmer!['last_name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ID: ${_farmer!['id_number']}'),
                          Text('Phone: ${_farmer!['phone_number']}'),
                        ],
                      ),
                    ),
                  ] else
                    const Text('Farmer information not available'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Claim Information
          const Text(
            'Claim Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          if (_claim!['claim_number'] != null)
            _buildInfoCard(
              'Claim Number',
              _claim!['claim_number'],
              icon: Icons.confirmation_number,
            ),

          _buildInfoCard(
            'Estimated Loss Amount',
            'KES ${_claim!['estimated_loss_amount']}',
            icon: Icons.attach_money,
          ),

          _buildInfoCard(
            'Assessment Date',
            _formatDate(_claim!['created_at']),
            icon: Icons.calendar_today,
          ),

          const SizedBox(height: 16),

          // Location Information
          if (_claim!['latitude'] != null && _claim!['longitude'] != null) ...[
            const Text(
              'Location',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Latitude: ${_claim!['latitude']}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'Longitude: ${_claim!['longitude']}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Assessment Notes
          const Text(
            'Assessment Notes',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _claim!['assessor_notes'] ?? 'No notes provided',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Photos
          if (photosPaths.isNotEmpty) ...[
            const Text(
              'Photos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: photosPaths.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PhotoViewScreen(
                          photoPath: photosPaths[index],
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag: photosPaths[index],
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(photosPaths[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class PhotoViewScreen extends StatelessWidget {
  final String photoPath;

  const PhotoViewScreen({Key? key, required this.photoPath}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Hero(
          tag: photoPath,
          child: InteractiveViewer(
            child: Image.file(File(photoPath)),
          ),
        ),
      ),
    );
  }
}
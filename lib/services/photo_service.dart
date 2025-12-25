import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// PhotoService handles photo uploads for claims and inspections
///
/// Note: This service expects an ApiService-like object that has:
/// - baseUrl: String property
/// - headers: Map<String, String> property (with auth token)
/// - get(String path): Future<dynamic> method
class PhotoService {
  final dynamic _api;

  PhotoService(this._api);

  /// Upload a photo for a claim with optional GPS coordinates
  Future<Map<String, dynamic>> uploadClaimPhoto(
      File photo,
      int claimId, {
        String? caption,
        double? latitude,
        double? longitude,
      }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${_api.baseUrl}/claims/$claimId/upload_photo/'),
      );

      // Add auth headers
      request.headers.addAll(_api.headers as Map<String, String>);

      // Add photo file
      request.files.add(await http.MultipartFile.fromPath(
        'photo',
        photo.path,
        contentType: MediaType('image', 'jpeg'),
        filename: path.basename(photo.path),
      ));

      // Add optional fields
      if (caption != null) request.fields['caption'] = caption;
      if (latitude != null) request.fields['latitude'] = latitude.toString();
      if (longitude != null) request.fields['longitude'] = longitude.toString();

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        return json.decode(responseData);
      } else {
        throw Exception('Photo upload failed: ${response.statusCode} - $responseData');
      }
    } catch (e) {
      throw Exception('Photo upload error: $e');
    }
  }

  /// Upload a photo for an inspection with optional GPS coordinates
  Future<Map<String, dynamic>> uploadInspectionPhoto(
      File photo,
      int inspectionId, {
        String? caption,
        double? latitude,
        double? longitude,
      }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${_api.baseUrl}/inspections/$inspectionId/upload_photo/'),
      );

      request.headers.addAll(_api.headers as Map<String, String>);

      request.files.add(await http.MultipartFile.fromPath(
        'photo',
        photo.path,
        contentType: MediaType('image', 'jpeg'),
        filename: path.basename(photo.path),
      ));

      if (caption != null) request.fields['caption'] = caption;
      if (latitude != null) request.fields['latitude'] = latitude.toString();
      if (longitude != null) request.fields['longitude'] = longitude.toString();

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        return json.decode(responseData);
      } else {
        throw Exception('Photo upload failed: ${response.statusCode} - $responseData');
      }
    } catch (e) {
      throw Exception('Photo upload error: $e');
    }
  }

  /// Get all photos associated with a claim
  Future<List<Map<String, dynamic>>> getClaimPhotos(int claimId) async {
    try {
      final response = await _api.get('/claims/$claimId/photos/');

      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      } else if (response is Map && response.containsKey('photos')) {
        return List<Map<String, dynamic>>.from(response['photos']);
      } else {
        return [];
      }
    } catch (e) {
      print('Error fetching claim photos: $e');
      return [];
    }
  }

  /// Get all photos associated with an inspection
  Future<List<Map<String, dynamic>>> getInspectionPhotos(int inspectionId) async {
    try {
      final response = await _api.get('/inspections/$inspectionId/photos/');

      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      } else if (response is Map && response.containsKey('photos')) {
        return List<Map<String, dynamic>>.from(response['photos']);
      } else {
        return [];
      }
    } catch (e) {
      print('Error fetching inspection photos: $e');
      return [];
    }
  }

  /// Delete a photo by ID
  Future<bool> deletePhoto(int photoId) async {
    try {
      // Assuming your API has a delete endpoint
      final response = await http.delete(
        Uri.parse('${_api.baseUrl}/photos/$photoId/'),
        headers: _api.headers as Map<String, String>,
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print('Error deleting photo: $e');
      return false;
    }
  }
}
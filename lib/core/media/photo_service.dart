import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../location/location_service.dart';
import 'media_repository.dart';

/// Photos are stored in the server's database, which has little space, so they
/// are shrunk on the phone: 1280 px at quality 60 comes to roughly 150-300 KB
/// while crop damage stays clear enough to assess.
const photoMaxSide = 1280.0;
const photoJpegQuality = 60;

/// Takes photos and keeps a copy in app storage until they're uploaded.
class PhotoService {
  PhotoService({ImagePicker? picker, this.location = const LocationService()})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final LocationService location;

  /// Returns null if the officer cancelled.
  Future<CapturedPhoto?> capture({bool fromGallery = false, bool tagLocation = true}) async {
    final picked = await _picker.pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: photoJpegQuality,
      maxWidth: photoMaxSide,
      maxHeight: photoMaxSide,
    );
    if (picked == null) return null;

    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'photos'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ext = p.extension(picked.path).toLowerCase() == '.png' ? '.png' : '.jpg';
    final target = p.join(dir.path, '${newUuid()}$ext');
    await File(picked.path).copy(target);

    final fix = tagLocation ? await location.quick() : null;
    return CapturedPhoto(path: target, latitude: fix?.latitude, longitude: fix?.longitude);
  }
}

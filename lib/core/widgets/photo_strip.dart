import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/app_database.dart';
import '../media/media_repository.dart';
import '../media/photo_service.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Thumbnails of photos (saved or just taken) plus camera/gallery buttons.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.photos,
    this.onAdd,
    this.onRemove,
    this.emptyText = 'No photos yet',
  });

  final List<PhotoItem> photos;
  final ValueChanged<CapturedPhoto>? onAdd;
  final ValueChanged<PhotoItem>? onRemove;
  final String emptyText;

  Future<void> _take(BuildContext context, {required bool gallery}) async {
    try {
      final photo = await context.read<PhotoService>().capture(fromGallery: gallery);
      if (photo != null) onAdd?.call(photo);
    } catch (e) {
      if (context.mounted) showMessage(context, 'Could not take photo: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (photos.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(emptyText, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        )
      else
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _Thumb(photos[i], onRemove: onRemove),
          ),
        ),
      if (onAdd != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _take(context, gallery: false),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take photo'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _take(context, gallery: true),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery'),
            ),
          ),
        ]),
      ],
    ]);
  }
}

/// Either a queued photo or one captured in an unsaved form.
class PhotoItem {
  PhotoItem.saved(LocalPhoto this.saved)
      : captured = null,
        path = saved.path;
  PhotoItem.captured(CapturedPhoto this.captured)
      : saved = null,
        path = captured.path;

  final LocalPhoto? saved;
  final CapturedPhoto? captured;
  final String path;

  bool get uploaded => saved?.status == SyncStatus.synced;
  bool get failed => saved?.status == SyncStatus.error;
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.item, {this.onRemove});
  final PhotoItem item;
  final ValueChanged<PhotoItem>? onRemove;

  @override
  Widget build(BuildContext context) {
    final file = File(item.path);
    final canRemove = onRemove != null && !item.uploaded;
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 96,
          child: file.existsSync()
              ? Image.file(file, fit: BoxFit.cover, cacheWidth: 256)
              : Container(
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image_outlined),
                ),
        ),
      ),
      Positioned(
        left: 4,
        bottom: 4,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Icon(
            item.uploaded
                ? Icons.cloud_done
                : item.failed
                    ? Icons.error
                    : Icons.cloud_upload_outlined,
            size: 16,
            color: item.uploaded
                ? AppTheme.success
                : item.failed
                    ? AppTheme.danger
                    : AppTheme.warning,
          ),
        ),
      ),
      if (canRemove)
        Positioned(
          right: 0,
          top: 0,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(backgroundColor: Colors.black45),
            icon: const Icon(Icons.close, size: 16, color: Colors.white),
            tooltip: 'Remove photo',
            onPressed: () => onRemove!(item),
          ),
        ),
    ]);
  }
}

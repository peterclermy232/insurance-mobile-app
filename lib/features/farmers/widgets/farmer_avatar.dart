import 'dart:io';

import 'package:flutter/material.dart';

/// Profile photo: the local file if we have one, else the server copy, else initials.
class FarmerAvatar extends StatelessWidget {
  const FarmerAvatar({super.key, required this.initials, this.localPath, this.url, this.radius = 22});

  final String initials;
  final String? localPath;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(initials, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
    );
    final path = localPath;
    if (path != null && File(path).existsSync()) {
      return CircleAvatar(radius: radius, backgroundImage: FileImage(File(path)));
    }
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }
    return fallback;
  }
}

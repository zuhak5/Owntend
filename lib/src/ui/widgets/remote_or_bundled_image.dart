import 'dart:io';

import 'package:flutter/material.dart';

class RemoteOrBundledImage extends StatelessWidget {
  const RemoteOrBundledImage({
    super.key,
    required this.assetPath,
    this.cachedRemotePath,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.semanticLabel,
  });

  final String assetPath;
  final String? cachedRemotePath;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (cachedRemotePath != null && cachedRemotePath!.isNotEmpty) {
      final file = File(cachedRemotePath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          semanticLabel: semanticLabel,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            assetPath,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            filterQuality: filterQuality,
            semanticLabel: semanticLabel,
          ),
        );
      }
    }

    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      semanticLabel: semanticLabel,
    );
  }
}

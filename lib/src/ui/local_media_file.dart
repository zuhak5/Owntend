import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<File?> localMediaFile(String? relativePath) async {
  if (relativePath == null || relativePath.trim().isEmpty) return null;
  final path = relativePath.trim();
  final file = p.isAbsolute(path)
      ? File(path)
      : File(
          p.joinAll([
            (await getApplicationDocumentsDirectory()).path,
            ...path.split('/'),
          ]),
        );
  return await file.exists() ? file : null;
}

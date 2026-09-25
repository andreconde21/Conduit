import 'dart:convert';
import 'package:flutter/services.dart';

/// The host companion files shipped inside the app (`assets/companion/`,
/// refreshed by `tools/bundle-companion.sh`).
class CompanionBundle {
  const CompanionBundle({required this.version, required this.files});

  /// `host/package.json` version at bundling time.
  final String version;

  /// Relative path (`bin/conductore-hostd`, `install.sh`, …) → contents.
  final Map<String, Uint8List> files;

  static const assetRoot = 'assets/companion';

  /// Reads the manifest and every file it lists from [bundle].
  static Future<CompanionBundle> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    final manifest =
        jsonDecode(await assets.loadString('$assetRoot/manifest.json'))
            as Map<String, Object?>;
    final version = manifest['version']! as String;
    final paths = (manifest['files']! as List<Object?>).cast<String>();
    final files = <String, Uint8List>{};
    for (final path in paths) {
      final data = await assets.load('$assetRoot/$path');
      files[path] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    }
    return CompanionBundle(version: version, files: files);
  }

  /// Directories (relative) that must exist before the files are written.
  Set<String> get directories => {
    for (final path in files.keys)
      if (path.contains('/')) path.substring(0, path.lastIndexOf('/')),
  };
}

typedef CompanionBundleLoader = Future<CompanionBundle> Function();

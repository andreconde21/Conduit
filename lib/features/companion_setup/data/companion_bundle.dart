import 'dart:convert';
import 'package:flutter/services.dart';

/// The host companion shipped inside the app: one archive
/// (`assets/companion/companion.tar.gz`) plus its manifest, both written by
/// `tools/bundle-companion.sh`.
///
/// It is an archive rather than loose files because App Store Connect
/// rejects any script (a file starting with `#!`) inside an iOS app as
/// unsigned code. The installer unpacks it on the host.
class CompanionBundle {
  const CompanionBundle({
    required this.version,
    required this.archive,
    this.archiveName = defaultArchiveName,
    this.checksums = const {},
  });

  /// `host/package.json` version at bundling time.
  final String version;

  /// The gzipped tar holding `bin/`, `lib/`, `install.sh`, … .
  final Uint8List archive;

  /// File name of [archive], kept when it is uploaded.
  final String archiveName;

  /// Relative path inside the archive (`bin/conductore-hostd`, …) → its
  /// lowercase hex sha256, checked on the host after unpacking.
  final Map<String, String> checksums;

  static const assetRoot = 'assets/companion';
  static const defaultArchiveName = 'companion.tar.gz';

  static final _safePath = RegExp(r'^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$');
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Reads the manifest and the archive it names from [bundle].
  static Future<CompanionBundle> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    final manifest =
        jsonDecode(await assets.loadString('$assetRoot/manifest.json'))
            as Map<String, Object?>;
    final version = manifest['version']! as String;
    final archiveName = manifest['archive']! as String;
    final checksums = (manifest['files']! as Map<String, Object?>).map(
      (path, hash) => MapEntry(path, hash! as String),
    );
    // Both end up in a shell command on the host; the manifest is ours,
    // but a malformed one must not become a command.
    if (!_safePath.hasMatch(archiveName)) {
      throw FormatException('bad archive name in manifest: $archiveName');
    }
    for (final MapEntry(key: path, value: hash) in checksums.entries) {
      if (!_safePath.hasMatch(path) ||
          path.split('/').contains('..') ||
          !_sha256.hasMatch(hash)) {
        throw FormatException('bad manifest entry: $path');
      }
    }
    final data = await assets.load('$assetRoot/$archiveName');
    return CompanionBundle(
      version: version,
      archiveName: archiveName,
      archive: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      checksums: checksums,
    );
  }

  /// Lines for `sha256sum -c` / `shasum -a 256 -c`, sorted by path.
  List<String> get checksumLines => [
    for (final path in checksums.keys.toList()..sort())
      '${checksums[path]}  $path',
  ];
}

typedef CompanionBundleLoader = Future<CompanionBundle> Function();

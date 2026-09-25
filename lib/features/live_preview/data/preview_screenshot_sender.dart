import 'dart:io';

import 'package:conduit/features/live_preview/domain/preview_screenshot.dart';
import 'package:conduit/features/share_target/domain/shared_payload.dart';
import 'package:path_provider/path_provider.dart';

/// Gets a Live preview screenshot to Claude: writes it to the app cache,
/// uploads it with the same path as images attached in Chat mode (the
/// host's share inbox over SFTP), and returns the draft text to insert.
class PreviewScreenshotSender {
  PreviewScreenshotSender({
    required this.upload,
    Future<Directory> Function()? tempRoot,
    DateTime Function()? clock,
  }) : _tempRoot = tempRoot ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  /// Uploads the file and returns its path on the host.
  final Future<String> Function(SharedFile file) upload;
  final Future<Directory> Function() _tempRoot;
  final DateTime Function() _clock;

  /// Resolves to the draft: the remote path and a note on what it shows.
  Future<String> send(PreviewScreenshot shot) async {
    final root = await _tempRoot();
    final dir = Directory(
      '${root.path}/prompt-images/preview-${_clock().microsecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    final name = previewScreenshotFileName(_clock(), shot.port);
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(shot.png, flush: true);
    final remotePath = await upload(
      SharedFile(
        path: file.path,
        name: name,
        size: shot.png.length,
        mimeType: 'image/png',
      ),
    );
    return previewScreenshotDraft(remotePath, shot);
  }
}

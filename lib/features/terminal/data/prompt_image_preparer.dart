import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:conduit/features/share_target/domain/shared_payload.dart';
import 'package:conduit/features/terminal/domain/prompt_image.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Turns a picked image into the file that is uploaded, in a fresh
/// `<temp>/prompt-images/<id>/` directory (the uploader deletes the file and
/// that directory afterwards).
///
/// An untouched crop copies the bytes as they are. A real crop decodes the
/// image with the engine's codecs (dart:ui, no extra package), draws the
/// cropped region scaled so its longest edge is at most [maxDimension], and
/// writes it as PNG.
///
/// The picked file is deleted afterwards when it lives under [tempRoot]
/// (picker and clipboard copies do), so attachments do not pile up.
class PromptImagePreparer {
  PromptImagePreparer({
    Future<Directory> Function()? tempRoot,
    DateTime Function()? clock,
    this.maxDimension = 2048,
  }) : _tempRoot = tempRoot ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _tempRoot;
  final DateTime Function() _clock;
  final int maxDimension;

  Future<SharedFile> prepare(SharedFile image, ui.Rect crop) async {
    final root = await _tempRoot();
    final dir = Directory(
      p.join(root.path, 'prompt-images', const Uuid().v4()),
    );
    await dir.create(recursive: true);
    final SharedFile prepared;
    if (isFullImageCrop(crop)) {
      final extension = p.extension(image.name).isNotEmpty
          ? p.extension(image.name)
          : p.extension(image.path);
      final target = File(
        p.join(dir.path, promptImageFileName(_clock(), extension)),
      );
      await File(image.path).copy(target.path);
      prepared = SharedFile(
        path: target.path,
        name: p.basename(target.path),
        size: await target.length(),
        mimeType: image.mimeType,
      );
    } else {
      final bytes = await _cropToPng(
        await File(image.path).readAsBytes(),
        crop,
      );
      final target = File(
        p.join(dir.path, promptImageFileName(_clock(), 'png')),
      );
      await target.writeAsBytes(bytes, flush: true);
      prepared = SharedFile(
        path: target.path,
        name: p.basename(target.path),
        size: bytes.length,
        mimeType: 'image/png',
      );
    }
    await _discardSource(image, root);
    return prepared;
  }

  Future<List<int>> _cropToPng(List<int> encoded, ui.Rect crop) async {
    final codec = await ui.instantiateImageCodec(
      encoded is Uint8List ? encoded : Uint8List.fromList(encoded),
    );
    final frame = await codec.getNextFrame();
    final source = frame.image;
    codec.dispose();
    try {
      final width = source.width.toDouble();
      final height = source.height.toDouble();
      final region = ui.Rect.fromLTRB(
        (crop.left.clamp(0.0, 1.0) * width).floorToDouble(),
        (crop.top.clamp(0.0, 1.0) * height).floorToDouble(),
        (crop.right.clamp(0.0, 1.0) * width).ceilToDouble(),
        (crop.bottom.clamp(0.0, 1.0) * height).ceilToDouble(),
      );
      final longest = math.max(region.width, region.height);
      final scale = longest > maxDimension ? maxDimension / longest : 1.0;
      final outWidth = math.max(1, (region.width * scale).round());
      final outHeight = math.max(1, (region.height * scale).round());
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        region,
        ui.Rect.fromLTWH(0, 0, outWidth.toDouble(), outHeight.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(outWidth, outHeight);
      picture.dispose();
      try {
        final data = await output.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('The image could not be encoded.');
        }
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        output.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  Future<void> _discardSource(SharedFile image, Directory root) async {
    try {
      final source = File(image.path);
      if (p.isWithin(root.path, source.absolute.path) &&
          await source.exists()) {
        await source.delete();
        final parent = source.parent;
        if (p.basename(p.dirname(parent.path)) == 'prompt-images' &&
            await parent.list().isEmpty) {
          await parent.delete();
        }
      }
    } catch (_) {
      // Best effort: the OS clears the cache eventually.
    }
  }
}

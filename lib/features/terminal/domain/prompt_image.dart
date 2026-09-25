import 'dart:ui' show Rect;

import 'package:conduit/features/share_target/domain/shared_payload.dart';

/// Where the Chat composer takes an image from.
enum PromptImageOrigin { gallery, camera, clipboard }

/// Hands the composer a local copy of an image, or null when the user
/// backed out (or, for [PromptImageOrigin.clipboard], nothing is there).
abstract interface class PromptImageSource {
  Future<SharedFile?> pick(PromptImageOrigin origin);
}

/// Everything the composer needs to attach an image to a prompt: pick it,
/// let the user crop it, turn it into the file to send, and upload it.
class PromptImageAttacher {
  const PromptImageAttacher({
    required this.source,
    required this.crop,
    required this.prepare,
    required this.upload,
  });

  final PromptImageSource source;

  /// Resolves to the normalized (0..1) crop rectangle, the full image when
  /// untouched, or null when the user cancelled.
  final Future<Rect?> Function(SharedFile image) crop;

  /// Writes the image to send (cropped and scaled when [crop] is not the
  /// whole image) and returns it.
  final Future<SharedFile> Function(SharedFile image, Rect crop) prepare;

  /// Uploads the prepared image and returns its path on the host.
  final Future<String> Function(SharedFile image) upload;
}

/// The full-image crop.
const fullImageCrop = Rect.fromLTRB(0, 0, 1, 1);

/// Whether [crop] keeps (nearly) the whole image, so no re-encode is needed.
bool isFullImageCrop(Rect crop) =>
    crop.left <= 0.001 &&
    crop.top <= 0.001 &&
    crop.right >= 0.999 &&
    crop.bottom >= 0.999;

/// A space-free, sortable remote file name: `image-20260925-143005.png`.
/// Claude Code picks image paths out of a prompt; spaces would break that.
String promptImageFileName(DateTime time, String extension) {
  String two(int value) => value.toString().padLeft(2, '0');
  final ext = extension.startsWith('.') ? extension.substring(1) : extension;
  return 'image-${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}.'
      '${ext.isEmpty ? 'png' : ext.toLowerCase()}';
}

/// Inserts [path] into [text] at [start]..[end] as its own word: a space is
/// added before it unless it starts a line, and one after it.
({String text, int cursor}) insertPromptImagePath(
  String text,
  int start,
  int end,
  String path,
) {
  final before = text.substring(0, start);
  final after = text.substring(end);
  final needsLeadingSpace =
      before.isNotEmpty && !before.endsWith(' ') && !before.endsWith('\n');
  final needsTrailingSpace = !after.startsWith(' ') && !after.startsWith('\n');
  final inserted =
      '${needsLeadingSpace ? ' ' : ''}$path${needsTrailingSpace ? ' ' : ''}';
  return (text: '$before$inserted$after', cursor: start + inserted.length);
}

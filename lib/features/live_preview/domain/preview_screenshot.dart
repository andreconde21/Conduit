import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:conduit/features/live_preview/domain/preview_viewport.dart';

/// A capture of the Live preview, ready to hand to Claude.
class PreviewScreenshot {
  const PreviewScreenshot({
    required this.png,
    required this.port,
    required this.path,
    this.viewport = PreviewViewport.phone,
    this.note = '',
  });

  /// The (possibly annotated) image, PNG encoded.
  final Uint8List png;

  /// The host port and path the preview showed.
  final int port;
  final String path;
  final PreviewViewport viewport;

  /// What the user typed on the annotate screen.
  final String note;
}

/// A shape drawn over a screenshot, in 0..1 image coordinates so it keeps
/// its place at any display size.
class PreviewAnnotation {
  const PreviewAnnotation({
    required this.kind,
    required this.start,
    required this.end,
  });

  final PreviewAnnotationKind kind;
  final Offset start;
  final Offset end;

  PreviewAnnotation copyWith({Offset? end}) =>
      PreviewAnnotation(kind: kind, start: start, end: end ?? this.end);

  /// Too small to be deliberate (a tap rather than a drag).
  bool get isTiny => (end - start).distance < 0.01;
}

enum PreviewAnnotationKind { rectangle, arrow }

/// A space-free, sortable file name: `preview-5173-20260925-143005.png`.
String previewScreenshotFileName(DateTime time, int port) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'preview-$port-${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}.png';
}

/// The prompt text inserted into the chat draft: the uploaded path (Claude
/// Code reads images by path), what it shows, and the user's note.
String previewScreenshotDraft(String remotePath, PreviewScreenshot shot) {
  final where = 'http://localhost:${shot.port}${shot.path}';
  final width = shot.viewport == PreviewViewport.phone
      ? ''
      : ' at ${shot.viewport.label.toLowerCase()} width '
            '(${shot.viewport.cssWidth!.round()}px)';
  final note = shot.note.trim();
  return '$remotePath\n'
      'Screenshot of $where in the phone\'s Live preview$width.'
      '${note.isEmpty ? '' : ' $note'}';
}

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Takes a PNG of what a widget shows on screen, WebView included.
abstract interface class PreviewScreenCapture {
  /// Captures [boundary] as it is on screen, at [pixelRatio] physical
  /// pixels per logical pixel.
  Future<Uint8List> capture(RenderRepaintBoundary boundary, double pixelRatio);
}

/// Thrown when nothing usable could be captured.
class PreviewCaptureException implements Exception {
  const PreviewCaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// On Android the WebView is a platform view whose pixels Flutter's
/// `toImage` cannot read (it comes back blank), so the region is copied
/// from the window with PixelCopy (`conduit/screen_capture`). Elsewhere, or
/// when PixelCopy is unavailable (Android 7), `toImage` is used, and a
/// fully transparent result is reported as a failure instead of sent.
class PlatformPreviewScreenCapture implements PreviewScreenCapture {
  const PlatformPreviewScreenCapture({
    this._channel = const MethodChannel('conduit/screen_capture'),
    this._platform,
  });

  final MethodChannel _channel;
  final TargetPlatform? _platform;

  @override
  Future<Uint8List> capture(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    if ((_platform ?? defaultTargetPlatform) == TargetPlatform.android) {
      final rect = boundary.localToGlobal(Offset.zero) & boundary.size;
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('capture', {
          'left': (rect.left * pixelRatio).round(),
          'top': (rect.top * pixelRatio).round(),
          'width': (rect.width * pixelRatio).round(),
          'height': (rect.height * pixelRatio).round(),
        });
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } on PlatformException {
        // Fall through to toImage.
      } on MissingPluginException {
        // Fall through to toImage.
      }
    }
    return captureBoundary(boundary, pixelRatio);
  }

  /// Flutter's own rendering of [boundary]; throws when it is blank.
  static Future<Uint8List> captureBoundary(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final raw = await image.toByteData();
      if (raw == null || isBlank(raw)) {
        throw const PreviewCaptureException(
          'The page could not be captured on this device.',
        );
      }
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw const PreviewCaptureException('The capture could not be saved.');
      }
      return png.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Whether RGBA [pixels] are all fully transparent (a platform view
  /// Flutter could not read).
  static bool isBlank(ByteData pixels) {
    for (var offset = 3; offset < pixels.lengthInBytes; offset += 4 * 97) {
      if (pixels.getUint8(offset) != 0) return false;
    }
    return true;
  }
}

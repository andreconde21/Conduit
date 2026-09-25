import 'dart:io';

import 'package:conduit/features/share_target/domain/shared_payload.dart';
import 'package:conduit/features/terminal/domain/prompt_image.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Gallery and camera through `image_picker` (Android's system photo
/// picker and camera app, so no storage or camera permission is needed),
/// and clipboard images through the app's own `conduit/clipboard_image`
/// channel, since Flutter's clipboard API only carries text.
class PlatformPromptImageSource implements PromptImageSource {
  PlatformPromptImageSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  static const _clipboardChannel = MethodChannel('conduit/clipboard_image');

  /// Longest edge of gallery and camera images. Claude downsizes anything
  /// larger before looking at it, so bigger only slows the upload.
  static const maxDimension = 2048.0;

  final ImagePicker _picker;

  @override
  Future<SharedFile?> pick(PromptImageOrigin origin) async {
    switch (origin) {
      case PromptImageOrigin.gallery:
      case PromptImageOrigin.camera:
        final picked = await _picker.pickImage(
          source: origin == PromptImageOrigin.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: maxDimension,
          maxHeight: maxDimension,
          imageQuality: 90,
          requestFullMetadata: false,
        );
        if (picked == null) {
          return null;
        }
        return SharedFile(
          path: picked.path,
          name: picked.name,
          size: await File(picked.path).length(),
          mimeType: picked.mimeType,
        );
      case PromptImageOrigin.clipboard:
        try {
          final raw = await _clipboardChannel.invokeMethod<Object?>(
            'readImage',
          );
          return SharedFile.fromMap(raw);
        } on MissingPluginException {
          return null;
        }
    }
  }
}

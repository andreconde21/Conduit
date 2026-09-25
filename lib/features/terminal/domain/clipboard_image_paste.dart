import 'package:conduit/features/share_target/domain/shared_payload.dart';
import 'package:conduit/features/terminal/domain/prompt_image.dart';

/// Pastes the phone clipboard's image as a file on the host: reads it,
/// names it `image-YYYYMMDD-HHMMSS.<ext>`, uploads it to the host's share
/// inbox and hands back the remote path, which the caller pastes where
/// text would go. Claude Code reads a pasted image path as an image.
///
/// Herdr 0.9.1 does the same over `herdr --remote` (Ctrl+V stages the
/// image on the server and pastes its path); here the file goes to the
/// per-host share inbox the other image features use, so it outlives the
/// session and the path is where the user expects it.
///
/// Built from the Chat mode composer's [PromptImageAttacher], so the
/// composer's "Paste image", the terminal paste and Chat View's paste all
/// read, name and upload images the same way.
class ClipboardImagePaster {
  const ClipboardImagePaster({
    required this.read,
    required this.prepare,
    required this.upload,
  });

  factory ClipboardImagePaster.fromAttacher(PromptImageAttacher attacher) =>
      ClipboardImagePaster(
        read: () => attacher.source.pick(PromptImageOrigin.clipboard),
        prepare: (image) => attacher.prepare(image, fullImageCrop),
        upload: attacher.upload,
      );

  /// The clipboard image as a local file, or null when it holds none.
  final Future<SharedFile?> Function() read;

  /// Copies it under the upload name.
  final Future<SharedFile> Function(SharedFile image) prepare;

  /// Uploads it and returns its path on the host.
  final Future<String> Function(SharedFile image) upload;

  /// Null when the clipboard holds no image (paste text instead); else the
  /// uploaded file's path on the host. Throws when the upload fails.
  ///
  /// [onUploading] runs once an image was found, before the upload, so the
  /// caller can show progress only when there is something to wait for.
  Future<String?> paste({void Function()? onUploading}) async {
    final image = await read();
    if (image == null) return null;
    onUploading?.call();
    return upload(await prepare(image));
  }
}

import 'dart:io';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';
import 'package:conduit/features/sftp/domain/sftp_session.dart';
import 'package:conduit/features/sftp/presentation/sftp_browser_controller.dart';
import 'package:conduit/features/share_target/domain/share_inbox.dart';
import 'package:conduit/features/share_target/domain/share_uploader.dart';
import 'package:conduit/features/share_target/domain/shared_payload.dart';

/// Uploads shared files into the host's inbox directory over SFTP, creating
/// the directory when missing. Cached copies are deleted once uploaded.
///
/// Local-shell hosts share the app sandbox with the cached copy, so the
/// cache path itself is returned and nothing is transferred.
class SftpShareUploader implements ShareUploader {
  const SftpShareUploader(this._repository);

  final SftpRepository _repository;

  @override
  Future<List<String>> upload(
    SavedHost host,
    List<SharedFile> files, {
    void Function(ShareUploadProgress progress)? onProgress,
  }) async {
    if (files.isEmpty) {
      return const [];
    }
    if (host.isLocal) {
      return [for (final file in files) file.path];
    }
    final session = await _repository.connect(host);
    try {
      final home = await session.resolve('.');
      final inbox = resolveShareInboxPath(
        configured: host.shareInboxDirectory,
        home: home,
      );
      final existing = await _ensureDirectory(session, inbox);
      final names = planShareFileNames(files, existing);
      final remotePaths = <String>[];
      for (var index = 0; index < files.length; index += 1) {
        final file = files[index];
        final upload = SftpUploadFile.local(
          localPath: file.path,
          name: names[index],
          size: file.size,
        );
        final remotePath = shareRemotePath(inbox, names[index]);
        try {
          await session.write(
            remotePath,
            upload.openRead(),
            file.size,
            onProgress: (sent) => onProgress?.call(
              ShareUploadProgress(
                fileName: names[index],
                index: index,
                count: files.length,
                sent: sent,
                total: file.size,
              ),
            ),
          );
        } catch (error) {
          throw AppFailure('Could not upload ${file.name}.', error);
        }
        remotePaths.add(remotePath);
        await _discardCache(file);
      }
      return remotePaths;
    } finally {
      await session.close();
    }
  }

  /// Creates [path] (and parents) when missing; returns the names already
  /// inside it so uploads can avoid overwriting.
  Future<Set<String>> _ensureDirectory(SftpSession session, String path) async {
    try {
      final entries = await session.list(path);
      return {for (final entry in entries) entry.name};
    } catch (_) {
      // Missing (or unreadable): create it, parents first.
    }
    final parent = path.substring(0, path.lastIndexOf('/'));
    if (parent.isNotEmpty && parent != path) {
      await _ensureDirectory(session, parent);
    }
    try {
      await session.makeDirectory(path);
    } catch (error) {
      throw AppFailure('Could not create the inbox directory $path.', error);
    }
    return {};
  }

  Future<void> _discardCache(SharedFile file) async {
    try {
      final cached = File(file.path);
      if (await cached.exists()) {
        await cached.delete();
      }
      final parent = cached.parent;
      if (await parent.exists() && (await parent.list().isEmpty)) {
        await parent.delete();
      }
    } catch (_) {
      // Cache cleanup is best-effort; the native side prunes stale copies.
    }
  }
}

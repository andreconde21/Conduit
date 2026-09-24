import 'dart:typed_data';

import 'package:conduit/features/sftp/domain/sftp_entry.dart';

abstract class SftpSession {
  Future<List<SftpEntry>> list(String path);

  Future<String> resolve(String path);

  /// Reads the whole file. When [maxBytes] is set the read fails with an
  /// `AppFailure` instead of buffering a file larger than that.
  Future<Uint8List> read(
    String path, {
    void Function(int bytesRead, int? total)? onProgress,
    int? maxBytes,
  });

  Future<void> write(
    String path,
    Stream<Uint8List> data,
    int length, {
    void Function(int bytesSent)? onProgress,
  });

  Future<void> makeDirectory(String path);

  Future<void> rename(String from, String to);

  Future<void> delete(SftpEntry entry);

  Future<void> close();
}

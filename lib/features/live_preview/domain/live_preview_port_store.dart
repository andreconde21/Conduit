import 'package:conduit/features/live_preview/domain/preview_viewport.dart';

/// Remembers the last previewed port per host, and the viewport chosen for
/// each port.
abstract class LivePreviewPortStore {
  Future<int?> read(String hostId);

  Future<void> write(String hostId, int port);

  /// The viewport last chosen for [port] on [hostId]; null when never set.
  Future<PreviewViewport?> readViewport(String hostId, int port);

  Future<void> writeViewport(String hostId, int port, PreviewViewport value);
}

class InMemoryLivePreviewPortStore implements LivePreviewPortStore {
  final Map<String, int> ports = {};
  final Map<String, PreviewViewport> viewports = {};

  @override
  Future<int?> read(String hostId) async => ports[hostId];

  @override
  Future<void> write(String hostId, int port) async => ports[hostId] = port;

  @override
  Future<PreviewViewport?> readViewport(String hostId, int port) async =>
      viewports['$hostId:$port'];

  @override
  Future<void> writeViewport(
    String hostId,
    int port,
    PreviewViewport value,
  ) async => viewports['$hostId:$port'] = value;
}

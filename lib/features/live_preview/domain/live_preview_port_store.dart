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

/// A [LivePreviewPortStore] that reads a machine without a port of its
/// own from another one ([fallbackHostOf]: "This computer" from the synced
/// machine that is this device). Writes stay with the machine asked for.
class FallbackLivePreviewPortStore implements LivePreviewPortStore {
  const FallbackLivePreviewPortStore(this._inner, this.fallbackHostOf);

  final LivePreviewPortStore _inner;
  final String? Function(String hostId) fallbackHostOf;

  @override
  Future<int?> read(String hostId) async {
    final own = await _inner.read(hostId);
    if (own != null) return own;
    final fallback = fallbackHostOf(hostId);
    return fallback == null ? null : _inner.read(fallback);
  }

  @override
  Future<void> write(String hostId, int port) => _inner.write(hostId, port);

  @override
  Future<PreviewViewport?> readViewport(String hostId, int port) async {
    final own = await _inner.readViewport(hostId, port);
    if (own != null) return own;
    final fallback = fallbackHostOf(hostId);
    return fallback == null ? null : _inner.readViewport(fallback, port);
  }

  @override
  Future<void> writeViewport(String hostId, int port, PreviewViewport value) =>
      _inner.writeViewport(hostId, port, value);
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

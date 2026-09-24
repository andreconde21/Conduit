/// Remembers the last previewed port per host.
abstract class LivePreviewPortStore {
  Future<int?> read(String hostId);

  Future<void> write(String hostId, int port);
}

class InMemoryLivePreviewPortStore implements LivePreviewPortStore {
  final Map<String, int> ports = {};

  @override
  Future<int?> read(String hostId) async => ports[hostId];

  @override
  Future<void> write(String hostId, int port) async => ports[hostId] = port;
}

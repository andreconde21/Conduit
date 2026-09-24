/// A loopback listener on the phone that tunnels to a port on the host.
abstract class LocalPortForward {
  /// Port bound on 127.0.0.1 that the WebView loads.
  int get localPort;

  int get remotePort;

  /// Failures of individual tunnelled connections (the app on the host went
  /// away, the SSH connection dropped). The forward itself stays open.
  Stream<String> get connectionErrors;

  /// Stops listening and closes every tunnelled connection.
  Future<void> close();
}

/// Opens [LocalPortForward]s to one host.
abstract class PortForwarder {
  /// Opens a forward to [remotePort] on the host's loopback interface.
  ///
  /// Throws an [AppFailure] when the host cannot be reached or nothing
  /// accepts connections on [remotePort], so the caller can explain it.
  Future<LocalPortForward> open(int remotePort);

  /// Releases the underlying connection. The forwarder must not be used
  /// after; forwards it opened are closed as well.
  Future<void> close();
}

import 'dart:async';
import 'dart:io';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/live_preview/domain/port_forward.dart';

/// Live preview on "This computer": the dev server already listens on this
/// machine's loopback, so the preview opens `http://127.0.0.1:<port>`
/// directly. No tunnel, only a check that something answers. A server
/// that listens on `::1` alone (Vite's `localhost` on recent Node) gets a
/// small IPv4 relay, since the preview loads 127.0.0.1.
class LocalPortForwarder implements PortForwarder {
  LocalPortForwarder({this.probeTimeout = const Duration(seconds: 2)});

  final Duration probeTimeout;
  bool _closed = false;

  @override
  Future<LocalPortForward> open(int remotePort) async {
    if (_closed) {
      throw const AppFailure('This preview is closed.');
    }
    if (await _answers(InternetAddress.loopbackIPv4, remotePort)) {
      return DirectLocalPort(remotePort);
    }
    if (await _answers(InternetAddress.loopbackIPv6, remotePort)) {
      final relay = await Ipv6LoopbackRelay.open(remotePort);
      _relays.add(relay);
      return relay;
    }
    throw AppFailure(
      'Nothing is listening on port $remotePort on this computer.',
    );
  }

  final Set<Ipv6LoopbackRelay> _relays = {};

  Future<bool> _answers(InternetAddress address, int port) async {
    try {
      final socket = await Socket.connect(address, port, timeout: probeTimeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final relay in _relays.toList()) {
      await relay.close();
    }
    _relays.clear();
  }
}

/// A "forward" that is the port itself.
class DirectLocalPort implements LocalPortForward {
  DirectLocalPort(this.remotePort);

  @override
  final int remotePort;

  @override
  int get localPort => remotePort;

  @override
  Stream<String> get connectionErrors => const Stream<String>.empty();

  @override
  Future<void> close() async {}
}

/// Listens on 127.0.0.1 and pipes each connection to `[::1]:<port>`.
class Ipv6LoopbackRelay implements LocalPortForward {
  Ipv6LoopbackRelay._(this._server, this.remotePort) {
    _server.listen(_accept);
  }

  static Future<Ipv6LoopbackRelay> open(int remotePort) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      return Ipv6LoopbackRelay._(server, remotePort);
    } catch (error) {
      throw AppFailure('Could not open a local port for the preview.', error);
    }
  }

  final ServerSocket _server;
  final Set<Socket> _sockets = {};
  final _errors = StreamController<String>.broadcast();

  @override
  final int remotePort;

  @override
  int get localPort => _server.port;

  @override
  Stream<String> get connectionErrors => _errors.stream;

  Future<void> _accept(Socket client) async {
    _sockets.add(client);
    try {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv6,
        remotePort,
      );
      _sockets.add(upstream);
      unawaited(
        client
            .cast<List<int>>()
            .pipe(upstream)
            .catchError((_) {})
            .whenComplete(() => _sockets.remove(upstream)),
      );
      unawaited(
        upstream
            .cast<List<int>>()
            .pipe(client)
            .catchError((_) {})
            .whenComplete(() => _sockets.remove(client)),
      );
    } catch (error) {
      if (!_errors.isClosed) _errors.add('$error');
      client.destroy();
      _sockets.remove(client);
    }
  }

  @override
  Future<void> close() async {
    await _server.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    _sockets.clear();
    await _errors.close();
  }
}

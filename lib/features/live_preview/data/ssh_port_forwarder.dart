import 'dart:async';
import 'dart:io';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/live_preview/domain/port_forward.dart';
import 'package:conduit/features/terminal/data/ssh_client_factory.dart';
import 'package:conduit/features/terminal/data/ssh_error_formatter.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:dartssh2/dartssh2.dart';

/// Port forwarding over a dedicated SSH connection (never the PTY one).
///
/// dartssh2 only opens `direct-tcpip` channels; the listener side is done
/// here: a [ServerSocket] on 127.0.0.1 accepts the WebView's connections
/// and pipes each one into its own forward channel, the same shape as
/// `ssh -L`. The connection is opened lazily by the first forward and kept
/// for later ones; a failure drops it so the next attempt reconnects.
class SshPortForwarder implements PortForwarder {
  SshPortForwarder(this._hostKeyVerifier, this._host);

  final HostKeyVerifier _hostKeyVerifier;
  final SavedHost _host;

  Future<SSHClient>? _client;
  final Set<SshLocalPortForward> _forwards = {};
  bool _closed = false;

  @override
  Future<LocalPortForward> open(int remotePort) async {
    if (_closed) {
      throw const AppFailure('This connection is closed.');
    }
    final client = await _connect();
    // Probe once so "nothing is listening" surfaces here, as a message,
    // instead of as a blank WebView error page later.
    try {
      final probe = await client.forwardLocal('127.0.0.1', remotePort);
      await probe.close();
    } catch (error) {
      if (client.isClosed) {
        await _dropClient();
        throw AppFailure(
          'Lost the connection to ${_host.name}.',
          describeSshConnectionError(error),
        );
      }
      throw AppFailure(
        'Nothing is listening on port $remotePort on ${_host.name}.',
        error,
      );
    }
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    } catch (error) {
      throw AppFailure('Could not open a local port for the preview.', error);
    }
    final forward = SshLocalPortForward(
      client,
      server,
      remotePort: remotePort,
    );
    _forwards.add(forward);
    unawaited(forward.done.then((_) => _forwards.remove(forward)));
    return forward;
  }

  Future<SSHClient> _connect() async {
    try {
      final client = await (_client ??= SshClientFactory(
        _hostKeyVerifier,
      ).connect(_host));
      if (client.isClosed) {
        await _dropClient();
        return _connect();
      }
      return client;
    } catch (error) {
      _client = null;
      throw AppFailure(
        'Could not reach ${_host.name}.',
        describeSshConnectionError(error),
      );
    }
  }

  Future<void> _dropClient() async {
    final pending = _client;
    _client = null;
    if (pending != null) {
      try {
        (await pending).close();
      } catch (_) {
        // The connection is already gone.
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final forward in List.of(_forwards)) {
      await forward.close();
    }
    await _dropClient();
  }
}

/// One loopback listener piping each accepted socket into a fresh
/// `direct-tcpip` channel to `127.0.0.1:remotePort` on the host.
class SshLocalPortForward implements LocalPortForward {
  SshLocalPortForward(
    this._client,
    this._server, {
    required this.remotePort,
    this.remoteHost = '127.0.0.1',
  }) {
    _subscription = _server.listen(
      _accept,
      onError: (Object error) => _errors.add('Local listener failed: $error'),
      onDone: _finish,
    );
  }

  final SSHClient _client;
  final ServerSocket _server;
  final String remoteHost;

  @override
  final int remotePort;

  late final StreamSubscription<Socket> _subscription;
  final _errors = StreamController<String>.broadcast();
  final _done = Completer<void>();
  final Set<Socket> _sockets = {};
  final Set<SSHForwardChannel> _channels = {};
  bool _closed = false;

  @override
  int get localPort => _server.port;

  @override
  Stream<String> get connectionErrors => _errors.stream;

  Future<void> get done => _done.future;

  int get activeConnections => _sockets.length;

  Future<void> _accept(Socket socket) async {
    _sockets.add(socket);
    socket.setOption(SocketOption.tcpNoDelay, true);
    final SSHForwardChannel channel;
    try {
      channel = await _client.forwardLocal(
        remoteHost,
        remotePort,
        localHost: '127.0.0.1',
        localPort: _server.port,
      );
    } catch (error) {
      _sockets.remove(socket);
      socket.destroy();
      if (!_errors.isClosed) {
        _errors.add(
          _client.isClosed
              ? 'The SSH connection dropped.'
              : 'Port $remotePort refused the connection.',
        );
      }
      return;
    }
    _channels.add(channel);
    void teardown() {
      if (_sockets.remove(socket)) {
        socket.destroy();
      }
      if (_channels.remove(channel)) {
        channel.destroy();
      }
    }

    unawaited(
      channel.stream
          .listen(
            socket.add,
            onError: (Object _) => teardown(),
            onDone: () {
              // Remote side finished: flush and half-close towards the
              // WebView so it sees end-of-response.
              socket.flush().then((_) => socket.close()).catchError((_) {});
            },
            cancelOnError: true,
          )
          .asFuture<void>()
          .catchError((Object _) {}),
    );
    unawaited(
      socket
          .listen(
            channel.sink.add,
            onError: (Object _) => teardown(),
            onDone: () {
              channel.sink.close();
            },
            cancelOnError: true,
          )
          .asFuture<void>()
          .catchError((Object _) {}),
    );
    unawaited(channel.done.then((_) => teardown(), onError: (_) => teardown()));
    unawaited(socket.done.then((_) => teardown(), onError: (_) => teardown()));
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    await _server.close();
    for (final socket in List.of(_sockets)) {
      socket.destroy();
    }
    _sockets.clear();
    for (final channel in List.of(_channels)) {
      channel.destroy();
    }
    _channels.clear();
    _finish();
  }

  void _finish() {
    if (!_done.isCompleted) {
      _done.complete();
    }
    if (!_errors.isClosed) {
      unawaited(_errors.close());
    }
  }
}

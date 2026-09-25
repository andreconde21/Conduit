import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sftp/domain/sftp_entry.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';
import 'package:conduit/features/sftp/domain/sftp_session.dart';
import 'package:conduit/features/this_computer/data/host_channels.dart';
import 'package:conduit/features/this_computer/data/local_file_repository.dart';
import 'package:conduit/features/this_computer/data/local_port_forwarder.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingFiles implements SftpRepository {
  final hosts = <String>[];

  @override
  Future<SftpSession> connect(SavedHost host) async {
    hosts.add(host.id);
    throw const AppFailure('recorded');
  }
}

void main() {
  final thisComputer = SavedHost.thisComputer();

  group('LocalFileRepository', () {
    late Directory home;
    late SftpSession files;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('conductore-files-');
      files = await LocalFileRepository(
        home: home.resolveSymbolicLinksSync(),
      ).connect(thisComputer);
    });

    tearDown(() => home.delete(recursive: true));

    test('resolves . and ~ to the home directory', () async {
      final root = home.resolveSymbolicLinksSync();
      expect(await files.resolve('.'), root);
      expect(await files.resolve('~'), root);
    });

    test('writes, lists, reads, renames and deletes', () async {
      final root = await files.resolve('.');
      await files.makeDirectory('$root/project');
      final bytes = Uint8List.fromList(utf8.encode('hello'));
      final progress = <int>[];
      await files.write(
        '$root/project/a.txt',
        Stream.value(bytes),
        bytes.length,
        onProgress: progress.add,
      );
      expect(progress.last, 5);

      final listing = await files.list(root);
      expect(listing.single.name, 'project');
      expect(listing.single.isDirectory, isTrue);
      final inner = await files.list('$root/project');
      expect(inner.single.path, '$root/project/a.txt');
      expect(inner.single.size, 5);
      expect(inner.single.kind, SftpEntryKind.file);

      expect(utf8.decode(await files.read('$root/project/a.txt')), 'hello');
      await expectLater(
        files.read('$root/project/a.txt', maxBytes: 2),
        throwsA(isA<AppFailure>()),
      );

      await files.rename('$root/project/a.txt', '$root/project/b.txt');
      final renamed = (await files.list('$root/project')).single;
      expect(renamed.name, 'b.txt');
      await files.delete(renamed);
      expect(await files.list('$root/project'), isEmpty);
      await files.delete((await files.list(root)).single);
      expect(await files.list(root), isEmpty);
    });

    test('relative paths are under home; failures are AppFailures', () async {
      final root = await files.resolve('.');
      await files.write('notes.md', Stream.value(Uint8List(3)), 3);
      expect(File('$root/notes.md').existsSync(), isTrue);
      await expectLater(
        files.list('$root/missing'),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('LocalPortForwarder', () {
    test('opens the port itself, with no tunnel', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) => socket.destroy());
      final forwarder = LocalPortForwarder();
      final forward = await forwarder.open(server.port);
      expect(forward.localPort, server.port);
      expect(forward.remotePort, server.port);
      await forwarder.close();
    });

    test('relays a server listening on ::1 only', () async {
      ServerSocket server;
      try {
        server = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
      } on SocketException {
        markTestSkipped('No IPv6 loopback here.');
        return;
      }
      addTearDown(server.close);
      server.listen((socket) {
        socket.write('pong');
        unawaited(socket.flush().then((_) => socket.close()));
      });
      final forwarder = LocalPortForwarder();
      final forward = await forwarder.open(server.port);
      expect(forward.localPort, isNot(server.port));
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        forward.localPort,
      );
      final reply = await utf8.decoder.bind(client).join();
      expect(reply, 'pong');
      client.destroy();
      await forwarder.close();
    });

    test('explains a port nothing listens on', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      await expectLater(
        LocalPortForwarder().open(port),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.message,
            'message',
            contains('Nothing is listening on port $port'),
          ),
        ),
      );
    });
  });

  test('RoutingSftpRepository sends This computer to local files', () async {
    final ssh = _RecordingFiles();
    final local = _RecordingFiles();
    final routing = RoutingSftpRepository(ssh: ssh, local: local);
    const saved = SavedHost(
      id: 'box',
      name: 'Box',
      host: 'box',
      port: 22,
      username: 'u',
      authMethod: SshAuthMethod.password,
    );
    for (final host in [
      thisComputer,
      thisComputer.copyWith(id: '$thisComputerHostId#tmux:main'),
      saved,
    ]) {
      await expectLater(routing.connect(host), throwsA(isA<AppFailure>()));
    }
    expect(local.hosts, [thisComputerHostId, '$thisComputerHostId#tmux:main']);
    expect(ssh.hosts, ['box']);
  });
}

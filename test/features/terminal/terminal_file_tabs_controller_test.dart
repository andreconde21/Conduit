import 'dart:typed_data';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sftp/domain/remote_file_kind.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';
import 'package:conduit/features/sftp/domain/sftp_session.dart';
import 'package:conduit/features/terminal/presentation/terminal_file_tabs_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

/// Fails the first [failures] connections, then hands out [session].
class FlakySftpRepository implements SftpRepository {
  FlakySftpRepository(this.session, {this.failures = 1});

  final FakeSftpSession session;
  int failures;
  int connectCalls = 0;

  @override
  Future<SftpSession> connect(SavedHost host) async {
    connectCalls++;
    if (failures > 0) {
      failures--;
      throw const AppFailure('connection refused');
    }
    return session;
  }
}

void main() {
  late FakeSftpSession session;
  late FakeSftpRepository repository;
  late TerminalFileTabsController controller;
  final hostA = buildHost('a');
  final hostB = buildHost('b');

  setUp(() {
    session = FakeSftpSession(home: '/home/user', tree: {});
    session.files['/etc/hosts'] = 'hello'.codeUnits;
    session.files['/home/user/notes.md'] = 'notes'.codeUnits;
    repository = FakeSftpRepository(session);
    controller = TerminalFileTabsController(repository);
  });

  tearDown(() => controller.dispose());

  test('open adds a tab once per host and path and activates it', () {
    var notifications = 0;
    controller.addListener(() => notifications++);

    final first = controller.open(hostA, '/etc/hosts');
    final again = controller.open(hostA, '/etc/hosts');
    final other = controller.open(hostB, '/etc/hosts');

    expect(identical(first, again), isTrue);
    expect(controller.tabs, [first, other]);
    expect(controller.active, other);
    expect(notifications, 3);
    expect(first.title, 'hosts');
  });

  test('activate ignores unknown tabs and accepts null for the terminal', () {
    final tab = controller.open(hostA, '/etc/hosts');
    final stranger = TerminalFileTab(host: hostA, path: '/etc/passwd');

    controller.activate(stranger);
    expect(controller.active, tab);

    controller.activate(null);
    expect(controller.active, isNull);
  });

  test('read resolves home-relative paths once and caps the size', () async {
    final tab = controller.open(hostA, '~/notes.md');

    final bytes = await controller.read(tab, null);
    await controller.read(tab, null);

    expect(String.fromCharCodes(bytes), 'notes');
    expect(session.resolveCalls, ['notes.md']);
    expect(session.readCalls, ['/home/user/notes.md', '/home/user/notes.md']);
    expect(session.readMaxBytes, everyElement(remoteFileViewerMaxBytes));
  });

  test('absolute paths skip resolution', () async {
    final tab = controller.open(hostA, '/etc/hosts');

    await controller.read(tab, null);

    expect(session.resolveCalls, isEmpty);
    expect(session.readCalls, ['/etc/hosts']);
  });

  test('write goes to the resolved path', () async {
    final tab = controller.open(hostA, '~/notes.md');

    await controller.write(tab, Uint8List.fromList('changed'.codeUnits));

    expect(
      String.fromCharCodes(session.writtenFiles['/home/user/notes.md']!),
      'changed',
    );
  });

  test('one session per host, closed when its last tab closes', () async {
    final first = controller.open(hostA, '/etc/hosts');
    final second = controller.open(hostA, '/home/user/notes.md');
    await controller.read(first, null);
    await controller.read(second, null);
    expect(session.closeCalls, 0);

    controller.close(first);
    await Future<void>.delayed(Duration.zero);
    expect(session.closeCalls, 0);
    expect(controller.active, second);

    controller.close(second);
    await Future<void>.delayed(Duration.zero);
    expect(session.closeCalls, 1);
    expect(controller.active, isNull);
    expect(controller.tabs, isEmpty);
  });

  test('closing an unknown tab is a no-op', () {
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.close(TerminalFileTab(host: hostA, path: '/nope'));

    expect(notifications, 0);
  });

  test('a failed connection is dropped so the next read reconnects', () async {
    final flaky = FlakySftpRepository(session);
    final retrying = TerminalFileTabsController(flaky);
    addTearDown(retrying.dispose);
    final tab = retrying.open(hostA, '/etc/hosts');

    await expectLater(retrying.read(tab, null), throwsA(isA<AppFailure>()));
    await Future<void>.delayed(Duration.zero);
    final bytes = await retrying.read(tab, null);

    expect(String.fromCharCodes(bytes), 'hello');
    expect(flaky.connectCalls, 2);
  });

  test('dispose closes every pooled session', () async {
    final tab = controller.open(hostA, '/etc/hosts');
    await controller.read(tab, null);

    controller.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(session.closeCalls, 1);
    // tearDown disposes again; ChangeNotifier tolerates it only once, so
    // swap in a fresh controller.
    controller = TerminalFileTabsController(repository);
  });
}

import 'dart:async';

import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/domain/network_connectivity.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:flutter/foundation.dart';

class TerminalWorkspaceController extends ChangeNotifier {
  TerminalWorkspaceController(this._repository, [this._connectivity]);

  final SshTerminalRepository _repository;
  final NetworkConnectivity? _connectivity;

  final List<TerminalSessionController> _sessions = [];
  int _activeIndex = 0;
  TerminalEnterSequence _enterSequence = TerminalEnterSequence.cr;

  List<TerminalSessionController> get sessions => List.unmodifiable(_sessions);

  TerminalSessionController? get activeSession {
    if (_sessions.isEmpty) {
      return null;
    }
    return _sessions[_activeIndex.clamp(0, _sessions.length - 1)];
  }

  bool get hasSessions => _sessions.isNotEmpty;

  int get liveSessionCount => _sessions
      .where(
        (session) =>
            session.status == TerminalConnectionStatus.connecting ||
            session.status == TerminalConnectionStatus.connected,
      )
      .length;

  bool get hasLiveSessions => liveSessionCount > 0;

  void setEnterSequence(TerminalEnterSequence sequence) {
    _enterSequence = sequence;
    for (final session in _sessions) {
      session.enterSequence = sequence;
    }
  }

  /// Opens (or activates) the session for [host]. [startupCommand] is typed
  /// into the shell once connected; it only applies to a newly created
  /// session.
  TerminalSessionController open(SavedHost host, {String? startupCommand}) {
    final existingIndex = _sessions.indexWhere(
      (session) => session.host.id == host.id,
    );
    if (existingIndex != -1) {
      _activeIndex = existingIndex;
      notifyListeners();
      return _sessions[existingIndex];
    }

    final session = TerminalSessionController(
      host: host,
      repository: _repository,
      connectivity: _connectivity,
      startupCommand: startupCommand,
      predictiveEchoEnabled: host.predictiveEchoEnabled,
      enterSequence: _enterSequence,
    );
    session.addListener(notifyListeners);
    _sessions.add(session);
    _activeIndex = _sessions.length - 1;
    notifyListeners();
    return session;
  }

  void activate(TerminalSessionController session) {
    final index = _sessions.indexOf(session);
    if (index == -1 || index == _activeIndex) {
      return;
    }
    _activeIndex = index;
    notifyListeners();
  }

  Future<void> close(TerminalSessionController session) async {
    final index = _sessions.indexOf(session);
    if (index == -1) {
      return;
    }

    _sessions.removeAt(index);
    if (_sessions.isEmpty) {
      _activeIndex = 0;
    } else if (_activeIndex >= _sessions.length) {
      _activeIndex = _sessions.length - 1;
    } else if (index < _activeIndex) {
      _activeIndex -= 1;
    }
    notifyListeners();

    session.removeListener(notifyListeners);
    await session.disconnect();
    session.dispose();
  }

  Future<void> closeAll() async {
    final sessions = List<TerminalSessionController>.from(_sessions);
    _sessions.clear();
    _activeIndex = 0;
    notifyListeners();

    for (final session in sessions) {
      session.removeListener(notifyListeners);
      await session.disconnect();
      session.dispose();
    }
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      session.removeListener(notifyListeners);
      session.dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}

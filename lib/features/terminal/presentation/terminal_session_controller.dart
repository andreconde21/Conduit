import 'dart:async';
import 'dart:convert';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/domain/network_connectivity.dart';
import 'package:conduit/features/terminal/domain/osc52_clipboard.dart';
import 'package:conduit/features/terminal/domain/predictive_echo.dart';
import 'package:conduit/features/terminal/domain/predictive_terminal_session.dart';
import 'package:conduit/features/terminal/domain/roaming_terminal_session.dart';
import 'package:conduit/features/terminal/domain/security_key_interaction.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_session.dart';
import 'package:conduit/features/terminal/domain/terminal_string_sequence_filter.dart';
import 'package:conduit/features/terminal/presentation/terminal_keyboard_controller.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/foundation.dart';

enum TerminalConnectionStatus {
  idle,
  connecting,
  connected,
  disconnected,
  failed,
}

class TerminalSessionController extends ChangeNotifier {
  TerminalSessionController({
    required this.host,
    required this.repository,
    this.connectivity,
    this.startupCommand,
    bool predictiveEchoEnabled = false,
    TerminalEnterSequence enterSequence = TerminalEnterSequence.cr,
  }) : keyboard = TerminalKeyboardController(defaultInputHandler),
       terminal = Terminal(maxLines: 10000) {
    _predictiveEchoEnabled = predictiveEchoEnabled;
    _enterSequence = enterSequence;
    _configureTerminal();
  }

  final SavedHost host;
  final SshTerminalRepository repository;
  final NetworkConnectivity? connectivity;

  /// Command typed into the shell right after connecting (e.g. a Herdr
  /// attach picked in the connect picker). Takes precedence over the host's
  /// tmux-on-connect settings.
  final String? startupCommand;
  final TerminalKeyboardController keyboard;
  final Terminal terminal;
  final _outputFilter = TerminalStringSequenceFilter();
  final _predictiveEcho = PredictiveEcho();
  final _terminalPaintNotifier = ChangeNotifier();
  final Stopwatch _inputClock = Stopwatch()..start();

  TerminalConnectionStatus _status = TerminalConnectionStatus.idle;
  SshTerminalSession? _session;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<void>? _doneSubscription;
  StreamSubscription<void>? _connectivitySubscription;
  StreamSubscription<int>? _echoAckSubscription;
  int _pixelWidth = 0;
  int _pixelHeight = 0;
  Timer? _resizeTimer;
  int _pendingColumns = 0;
  int _pendingRows = 0;
  bool _disconnecting = false;
  bool _disposed = false;
  bool _predictiveEchoEnabled = false;
  TerminalEnterSequence _enterSequence = TerminalEnterSequence.cr;
  int _connectionGeneration = 0;
  int? _lastIosEnterOutputMs;
  String _terminalTitle = '';
  final _remoteClipboardWrites = StreamController<String>.broadcast();

  static const _iosDuplicateEnterWindow = Duration(milliseconds: 80);
  static const _gracefulMoshCloseTimeout = Duration(milliseconds: 1500);
  static const _tmuxDetachExitDelay = Duration(milliseconds: 150);
  static const _connectSnippetAfterTmuxDelay = Duration(milliseconds: 250);

  TerminalConnectionStatus get status => _status;
  String get title => host.name;

  /// The window title the remote application last set (OSC 0/2), empty
  /// until one arrives. Herdr and tmux both keep it current.
  String get terminalTitle => _terminalTitle;
  /// Text the remote asked to put on the clipboard with OSC 52 (vim, tmux
  /// `set-clipboard on`, Claude Code's copy). Already decoded, capped at
  /// [osc52MaxBytes]; read requests are never answered. Whether it reaches
  /// the phone clipboard is the listener's decision (a user setting).
  Stream<String> get remoteClipboardWrites => _remoteClipboardWrites.stream;
  bool get isConnected => _status == TerminalConnectionStatus.connected;
  bool get predictiveEchoEnabled => _predictiveEchoEnabled;
  TerminalEnterSequence get enterSequence => _enterSequence;
  Listenable get terminalPaintListenable => _terminalPaintNotifier;

  /// Whether the remote application has enabled mouse tracking (DECSET
  /// 1000/1002/1003), meaning forwarded taps would actually be delivered
  /// as mouse clicks rather than ignored.
  bool get remoteMouseTrackingActive => terminal.mouseMode != MouseMode.none;

  List<TerminalCellOverlay> get overlays {
    if (!_predictiveEchoEnabled) {
      return const <TerminalCellOverlay>[];
    }

    return [
      for (final prediction in _predictiveEcho.overlay)
        TerminalCellOverlay(
          row: prediction.row,
          column: prediction.column,
          text: prediction.character,
          opacity: prediction.erase ? 1 : 0.62,
          erase: prediction.erase,
        ),
    ];
  }

  set predictiveEchoEnabled(bool enabled) {
    if (_predictiveEchoEnabled == enabled) {
      return;
    }
    _predictiveEchoEnabled = enabled;
    if (!enabled) {
      _predictiveEcho.reset();
    }
    _notifyTerminalPaint();
    notifyListeners();
  }

  set enterSequence(TerminalEnterSequence sequence) {
    if (_enterSequence == sequence) {
      return;
    }
    _enterSequence = sequence;
    notifyListeners();
  }

  bool get shouldConnect =>
      !_disconnecting &&
      (_status == TerminalConnectionStatus.idle ||
          _status == TerminalConnectionStatus.disconnected ||
          _status == TerminalConnectionStatus.failed);

  Future<void> connect() async {
    if (_status == TerminalConnectionStatus.connecting ||
        _status == TerminalConnectionStatus.connected ||
        _disconnecting ||
        _disposed) {
      return;
    }

    final generation = ++_connectionGeneration;
    _outputFilter.reset();
    _predictiveEcho.reset();
    _status = TerminalConnectionStatus.connecting;
    terminal.write(
      host.isLocal
          ? 'Starting ${host.name}...\r\n'
          : 'Connecting to ${host.endpoint}...\r\n',
    );
    notifyListeners();

    StreamSubscription<String>? securityKeySubscription;
    try {
      securityKeySubscription = SecurityKeyInteraction.instance.messages.listen(
        (message) => terminal.write('$message\r\n'),
      );
      final session = await repository.connect(
        host,
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );
      if (_disposed || generation != _connectionGeneration || _disconnecting) {
        unawaited(session.close());
        return;
      }
      _session = session;

      terminal.buffer.clear();
      terminal.buffer.setCursor(0, 0);
      if (kDebugMode) {
        debugPrint(
          '[term ${host.name}] connect size -> '
          '${terminal.viewWidth}x${terminal.viewHeight}',
        );
      }
      session.resize(
        terminal.viewWidth,
        terminal.viewHeight,
        _pixelWidth,
        _pixelHeight,
      );

      _stdoutSubscription = session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (chunk) => _writeTerminalOutput(_outputFilter.process(chunk)),
            onError: _handleStreamError,
          );
      _stderrSubscription = session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_writeTerminalOutput, onError: _handleStreamError);
      _doneSubscription = session.done.asStream().listen((_) {
        if (_status == TerminalConnectionStatus.connected) {
          _status = TerminalConnectionStatus.disconnected;
          terminal.write(
            host.isLocal
                ? '\r\nShell exited.\r\n'
                : '\r\nConnection closed.\r\n',
          );
          notifyListeners();
        }
      }, onError: _handleStreamError);

      if (session is RoamingTerminalSession) {
        _connectivitySubscription = connectivity?.onNetworkChanged.listen(
          (_) => _rehome(),
        );
      }
      if (session is PredictiveTerminalSession) {
        final predictiveSession = session as PredictiveTerminalSession;
        _predictiveEcho.updateSrtt(predictiveSession.smoothedRtt);
        _echoAckSubscription = predictiveSession.echoAcks.listen((int ackNum) {
          _predictiveEcho
            ..updateSrtt(predictiveSession.smoothedRtt)
            ..recordEchoAck(ackNum);
          _notifyTerminalPaint();
        }, onError: _handleStreamError);
      }

      _status = TerminalConnectionStatus.connected;
      notifyListeners();
      _runStartupCommandIfConfigured(session);
      _runConnectSnippetIfConfigured(session);
    } on AppFailure catch (failure) {
      if (_disposed || generation != _connectionGeneration) {
        return;
      }
      _fail(failure.toString());
    } catch (error) {
      if (_disposed || generation != _connectionGeneration) {
        return;
      }
      _fail('Connection failed: $error');
    } finally {
      await securityKeySubscription?.cancel();
    }
  }

  Future<void> disconnect() async {
    if (_disconnecting ||
        _status == TerminalConnectionStatus.disconnected ||
        _status == TerminalConnectionStatus.idle) {
      return;
    }
    _disconnecting = true;
    _connectionGeneration += 1;

    _resizeTimer?.cancel();
    _resizeTimer = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _doneSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _echoAckSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _doneSubscription = null;
    _connectivitySubscription = null;
    _echoAckSubscription = null;
    _predictiveEcho.reset();

    final session = _session;
    _session = null;
    try {
      await _closeRemoteMoshSession(session);
      await session?.close();
    } finally {
      keyboard.clearModifiers();
      _status = TerminalConnectionStatus.disconnected;
      if (!_disposed) {
        terminal.write('\r\nDisconnected.\r\n');
        notifyListeners();
      }
      _disconnecting = false;
    }
  }

  void sendKey(TerminalKey key) {
    terminal.keyInput(key, ctrl: keyboard.ctrl, alt: keyboard.alt);
    keyboard.clearModifiers();
  }

  void sendText(String text) {
    terminal.textInput(text);
    keyboard.clearModifiers();
  }

  void sendControl(TerminalKey key) {
    terminal.keyInput(key, ctrl: true);
    keyboard.clearModifiers();
  }

  /// Sends a multiplexer prefix (the host's tmux/Herdr prefix, usually).
  ///
  /// A plain Ctrl+letter or Ctrl+Space goes through [sendControl] so the
  /// terminal encodes it like any other control key; every other
  /// combination is written as its raw byte sequence.
  void sendPrefix(MultiplexerPrefixKey prefix) {
    final controlKey = prefix.controlKey;
    if (controlKey != null) {
      sendControl(controlKey);
      return;
    }
    sendText(prefix.sequence);
  }

  void paste(String text) {
    terminal.paste(text);
    keyboard.clearModifiers();
  }

  /// Whether the remote application has switched bracketed paste on
  /// (DECSET 2004), so pasted text is delivered atomically instead of being
  /// interpreted as individual key presses.
  bool get bracketedPasteSupported => terminal.bracketedPasteMode;

  static const composedEnterDelay = Duration(milliseconds: 120);

  /// Sends a composed, possibly multiline prompt into the terminal.
  ///
  /// The payload goes through the terminal's paste path: when the remote
  /// application advertises bracketed paste (DECSET 2004) the text — newlines,
  /// quotes, and all — is wrapped in paste markers and arrives as one literal
  /// block. Without bracketed paste the text falls back to the plain input
  /// path with newlines normalized to carriage returns, which is what each
  /// line's Enter key would have sent.
  ///
  /// Control characters other than tab and newline are stripped in both
  /// paths: a prompt copied from a terminal can carry ESC, ^C or ^D bytes
  /// that the remote application would act on as keystrokes, and inside a
  /// bracketed paste an embedded paste-end marker would let the rest of the
  /// text escape the paste guard.
  ///
  /// With [submit], Enter is delivered as a separate write shortly after the
  /// text. Some TUIs classify a single read that contains a long line ending
  /// in CR as a paste and insert the trailing CR literally instead of
  /// submitting; an isolated Enter keypress submits regardless.
  Future<void> sendComposed(String text, {required bool submit}) async {
    final sanitized = sanitizeComposedText(text);
    if (terminal.bracketedPasteMode) {
      terminal.paste(sanitized);
    } else {
      // Without bracketed paste, newlines are delivered as carriage returns
      // (what Enter sends). Trailing newlines are dropped so "insert only"
      // never submits the final line on its own.
      final normalized = sanitized
          .replaceAll(RegExp(r'\n+$'), '')
          .replaceAll('\n', '\r');
      terminal.textInput(normalized);
    }
    keyboard.clearModifiers();
    if (submit) {
      await Future<void>.delayed(composedEnterDelay);
      if (!_disposed) {
        terminal.keyInput(TerminalKey.enter);
      }
    }
  }

  /// Normalizes line endings to `\n` and strips every C0 control character
  /// except tab and newline (plus DEL), so composed text can only ever reach
  /// the remote application as printable input. Stripping ESC also removes
  /// any embedded bracketed-paste end marker.
  static String sanitizeComposedText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_composedControlCharacters, '');
  }

  static final _composedControlCharacters = RegExp(
    r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]',
  );

  bool get _hasStartupCommand =>
      startupCommand != null || host.startTmuxOnConnect;

  void _runStartupCommandIfConfigured(SshTerminalSession session) {
    final explicit = startupCommand;
    final command = explicit != null
        ? '$explicit${_enterSequence.value}'
        : _buildTmuxCommand();
    if (command == null) {
      return;
    }
    unawaited(
      session.send(utf8.encode(command)).catchError(_handleStreamError),
    );
  }

  void _runConnectSnippetIfConfigured(SshTerminalSession session) {
    final snippetId = host.connectSnippetId;
    if (snippetId.isEmpty) {
      return;
    }
    final snippet = host.snippets
        .where((candidate) => candidate.id == snippetId)
        .firstOrNull;
    if (snippet == null) {
      return;
    }
    final text = snippet.submit
        ? '${snippet.text}${_enterSequence.value}'
        : snippet.text;
    if (text.isEmpty) {
      return;
    }
    final delay = _hasStartupCommand
        ? _connectSnippetAfterTmuxDelay
        : Duration.zero;
    unawaited(_sendConnectSnippet(session, text, delay));
  }

  Future<void> _sendConnectSnippet(
    SshTerminalSession session,
    String text,
    Duration delay,
  ) async {
    try {
      await Future<void>.delayed(delay);
      if (_session != session ||
          _status != TerminalConnectionStatus.connected ||
          _disposed ||
          _disconnecting) {
        return;
      }
      await session.send(utf8.encode(text));
    } catch (error, stackTrace) {
      _handleStreamError(error, stackTrace);
    }
  }

  Future<void> _closeRemoteMoshSession(SshTerminalSession? session) async {
    if (session == null || !host.useMosh) {
      return;
    }
    try {
      if (host.startTmuxOnConnect) {
        await session.send(_tmuxDetachBytes());
        await Future<void>.delayed(_tmuxDetachExitDelay);
        await session.send(utf8.encode('exit\r'));
      } else {
        await session.send(const [0x04]);
      }
      await session.done.timeout(_gracefulMoshCloseTimeout);
    } catch (_) {
      // Fall back to the transport close below if the remote side ignores the
      // graceful exit sequence or the session is already gone.
    }
  }

  List<int> _tmuxDetachBytes() => [...host.tmuxPrefixKey.bytes, 0x64];

  @visibleForTesting
  String? buildTmuxCommandForTesting() => _buildTmuxCommand();

  String? _buildTmuxCommand() {
    if (!host.startTmuxOnConnect) {
      return null;
    }
    final sessionName = host.tmuxSessionName.trim().isEmpty
        ? defaultTmuxSessionName
        : host.tmuxSessionName.trim();
    final command = StringBuffer(
      'tmux new-session -A -s ${_shellQuote(sessionName)}',
    );
    final startDirectory = host.tmuxStartDirectory.trim();
    if (startDirectory.isNotEmpty) {
      command.write(' -c ${_shellQuote(startDirectory)}');
    }
    command.write(_enterSequence.value);
    return command.toString();
  }

  static final _unquotedPath = RegExp(r'^[A-Za-z0-9_~./:=+-]+$');

  static String _shellQuote(String value) => _unquotedPath.hasMatch(value)
      ? value
      : "'${value.replaceAll("'", r"'\''")}'";

  void _configureTerminal() {
    terminal.inputHandler = keyboard;
    terminal.onResize = (columns, rows, pixelWidth, pixelHeight) {
      _pixelWidth = pixelWidth;
      _pixelHeight = pixelHeight;
      _pendingColumns = columns;
      _pendingRows = rows;
      _resizeTimer?.cancel();
      _resizeTimer = Timer(const Duration(milliseconds: 250), _flushResize);
    };
    terminal.onOutput = _sendTerminalOutput;
    terminal.onTitleChange = (title) {
      if (title == _terminalTitle || _disposed) {
        return;
      }
      _terminalTitle = title;
      notifyListeners();
    };
    terminal.onPrivateOSC = _handlePrivateOsc;
  }

  void _handlePrivateOsc(String code, List<String> args) {
    if (_disposed) {
      return;
    }
    switch (code) {
      case '52':
        final text = decodeOsc52Payload(args);
        if (text != null) {
          _remoteClipboardWrites.add(text);
        }
    }
  }

  void _sendTerminalOutput(String data) {
    final normalized = _normalizeEnterOutput(data);
    if (_shouldSuppressDuplicateIosEnter(normalized)) {
      return;
    }

    final session = _session;
    if (session == null) {
      return;
    }

    final bytes = utf8.encode(normalized);
    if (_predictiveEchoEnabled && session is PredictiveTerminalSession) {
      final predictiveSession = session as PredictiveTerminalSession;
      try {
        final inputNum = predictiveSession.sendWithInputState(bytes);
        _predictiveEcho
          ..updateSrtt(predictiveSession.smoothedRtt)
          ..recordInput(
            normalized,
            inputNum: inputNum,
            cursorRow: terminal.absoluteCursorRow,
            cursorColumn: terminal.cursorColumn,
            viewWidth: terminal.viewWidth,
            altScreen: terminal.isUsingAltBuffer,
          );
        _notifyTerminalPaint();
      } catch (error, stackTrace) {
        _handleStreamError(error, stackTrace);
      }
      return;
    }

    unawaited(session.send(bytes).catchError(_handleStreamError));
  }

  bool _shouldSuppressDuplicateIosEnter(String data) {
    if (defaultTargetPlatform != TargetPlatform.iOS || !_isEnterOutput(data)) {
      if (data.isNotEmpty && !_isEnterOutput(data)) {
        _lastIosEnterOutputMs = null;
      }
      return false;
    }

    final now = _inputClock.elapsedMilliseconds;
    final last = _lastIosEnterOutputMs;
    _lastIosEnterOutputMs = now;

    return last != null &&
        now - last <= _iosDuplicateEnterWindow.inMilliseconds;
  }

  bool _isEnterOutput(String data) {
    return data == '\r' || data == '\n' || data == '\r\n';
  }

  String _normalizeEnterOutput(String data) {
    return _isEnterOutput(data) ? _enterSequence.value : data;
  }

  void _writeTerminalOutput(String data) {
    terminal.write(data);
    if (_predictiveEcho.hasPredictions) {
      _predictiveEcho.removeWhere(_isConfirmedPrediction);
      _notifyTerminalPaint();
    }
  }

  void _notifyTerminalPaint() {
    _terminalPaintNotifier.notifyListeners();
  }

  bool _isConfirmedPrediction(TerminalPrediction prediction) {
    if (prediction.erase) {
      return !_hasTerminalContentAt(prediction.row, prediction.column);
    }
    return _terminalCharacterAt(prediction.row, prediction.column) ==
            prediction.character ||
        _terminalCursorPassed(prediction.row, prediction.column);
  }

  bool _hasTerminalContentAt(int row, int column) {
    return _terminalCharacterAt(row, column) != null;
  }

  String? _terminalCharacterAt(int row, int column) {
    if (row < 0 || row >= terminal.buffer.lines.length) {
      return null;
    }
    final line = terminal.buffer.lines[row];
    if (column < 0 || column >= line.length) {
      return null;
    }
    final codePoint = line.getCodePoint(column);
    return codePoint == 0 ? null : String.fromCharCode(codePoint);
  }

  bool _terminalCursorPassed(int row, int column) {
    final cursorRow = terminal.absoluteCursorRow;
    if (row < cursorRow) {
      return true;
    }
    return row == cursorRow && column < terminal.cursorColumn;
  }

  void _rehome() {
    final session = _session;
    if (session is! RoamingTerminalSession ||
        _status != TerminalConnectionStatus.connected) {
      return;
    }
    final roaming = session as RoamingTerminalSession;
    unawaited(roaming.rehome().catchError(_handleStreamError));
  }

  void forceResize() {
    if (_session == null || _status != TerminalConnectionStatus.connected) {
      return;
    }
    _pendingColumns = terminal.viewWidth;
    _pendingRows = terminal.viewHeight;
    _resizeTimer?.cancel();
    _flushResize();
  }

  void _flushResize() {
    final session = _session;
    if (session == null) return;
    if (kDebugMode) {
      debugPrint(
        '[term ${host.name}] -> server ${_pendingColumns}x$_pendingRows',
      );
    }
    session.resize(_pendingColumns, _pendingRows, _pixelWidth, _pixelHeight);
  }

  void _handleStreamError(Object error, [StackTrace? stackTrace]) {
    if (_disposed || _status != TerminalConnectionStatus.connected) {
      return;
    }
    terminal.write('\r\n$error\r\n');
    _status = TerminalConnectionStatus.failed;
    notifyListeners();
  }

  void _fail(String message) {
    if (_disposed) {
      return;
    }
    _status = TerminalConnectionStatus.failed;
    terminal.write('\r\n$message\r\n');
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionGeneration += 1;
    _resizeTimer?.cancel();
    unawaited(_stdoutSubscription?.cancel());
    unawaited(_stderrSubscription?.cancel());
    unawaited(_doneSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_echoAckSubscription?.cancel());
    final session = _session;
    _session = null;
    if (session != null) {
      unawaited(session.close());
    }
    keyboard.dispose();
    _terminalPaintNotifier.dispose();
    unawaited(_remoteClipboardWrites.close());
    super.dispose();
  }
}

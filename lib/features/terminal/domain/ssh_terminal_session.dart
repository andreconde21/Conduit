abstract interface class SshTerminalSession {
  Stream<List<int>> get stdout;

  Stream<List<int>> get stderr;

  Future<void> get done;

  Future<void> send(List<int> data);

  void resize(int columns, int rows, int pixelWidth, int pixelHeight);

  Future<void> close();
}

/// A session whose far end is a local process with an exit code (the
/// desktop's own shell), so an ended session can say how it ended.
abstract interface class ExitStatusTerminalSession {
  /// Completes with the shell's exit code once it has ended. On Linux and
  /// macOS a negative value is the signal that ended it.
  Future<int> get exitCode;
}

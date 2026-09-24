class AppFailure implements Exception {
  const AppFailure(this.message, [this.cause]);

  final String message;
  final Object? cause;

  /// [message], followed by [cause] when it is already user-facing text
  /// (a formatted SSH error, a command's stderr). Other causes are
  /// exception objects and stay out of the UI.
  String get userMessage {
    final detail = cause;
    if (detail is String && detail.trim().isNotEmpty) {
      return '$message\n${detail.trim()}';
    }
    return message;
  }

  @override
  String toString() => cause == null ? message : '$message ($cause)';
}

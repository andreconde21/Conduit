import 'package:flutter/widgets.dart';

/// Streams a dictation transcript into a [TextEditingController].
///
/// The insertion point is captured once when dictation starts: whatever was
/// selected is replaced, and every partial transcript overwrites the previous
/// partial (never the surrounding text). A space is added before the
/// transcript when the preceding character is not whitespace, so dictating
/// after typed text reads naturally.
class DictationTextInserter {
  DictationTextInserter(this.controller);

  final TextEditingController controller;

  String _before = '';
  String _after = '';
  String _separator = '';
  bool _active = false;

  bool get isActive => _active;

  void begin() {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    _before = text.substring(0, start);
    _after = text.substring(end);
    _separator = _before.isEmpty || RegExp(r'\s$').hasMatch(_before) ? '' : ' ';
    _active = true;
  }

  void partial(String transcript) => _apply(transcript);

  /// Applies the final transcript and stops tracking. An empty transcript
  /// leaves the text as it was before dictation started.
  void finish(String transcript) {
    if (!_active) {
      return;
    }
    _apply(transcript);
    _active = false;
  }

  /// Restores the text captured at [begin]; used when the session fails
  /// before any transcript arrived.
  void cancel() {
    if (!_active) {
      return;
    }
    _active = false;
    controller.value = TextEditingValue(
      text: _before + _after,
      selection: TextSelection.collapsed(offset: _before.length),
    );
  }

  void _apply(String transcript) {
    if (!_active) {
      return;
    }
    if (transcript.isEmpty) {
      controller.value = TextEditingValue(
        text: _before + _after,
        selection: TextSelection.collapsed(offset: _before.length),
      );
      return;
    }
    final inserted = _separator + transcript;
    controller.value = TextEditingValue(
      text: _before + inserted + _after,
      selection: TextSelection.collapsed(
        offset: _before.length + inserted.length,
      ),
    );
  }
}

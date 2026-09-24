import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/foundation.dart';

class TerminalKeyboardController extends TerminalInputHandler
    with ChangeNotifier {
  TerminalKeyboardController(this._delegate);

  final TerminalInputHandler _delegate;

  bool _ctrl = false;
  bool _alt = false;
  bool _ctrlLatched = false;

  /// Whether the next key is sent with ctrl: a one-shot toggle, or the latch.
  bool get ctrl => _ctrl || _ctrlLatched;
  bool get alt => _alt;

  /// Sticky ctrl: stays on across keys until released, unlike the one-shot
  /// [ctrl] toggle which [clearModifiers] resets after every key.
  bool get ctrlLatched => _ctrlLatched;

  set ctrlLatched(bool value) {
    if (_ctrlLatched == value) {
      return;
    }
    _ctrlLatched = value;
    _ctrl = false;
    notifyListeners();
  }

  set ctrl(bool value) {
    // Turning ctrl off also releases the latch, so a plain toggle key can
    // always get back to a clean state.
    final releasesLatch = !value && _ctrlLatched;
    if (_ctrl == value && !releasesLatch) {
      return;
    }
    _ctrl = value;
    if (releasesLatch) {
      _ctrlLatched = false;
    }
    notifyListeners();
  }

  set alt(bool value) {
    if (_alt == value) {
      return;
    }
    _alt = value;
    notifyListeners();
  }

  void clearModifiers() {
    if (!_ctrl && !_alt) {
      return;
    }
    _ctrl = false;
    _alt = false;
    notifyListeners();
  }

  @override
  String? call(TerminalKeyboardEvent event) {
    final usesToggledModifier = _ctrl || _alt;
    final result = _delegate.call(
      event.copyWith(ctrl: event.ctrl || ctrl, alt: event.alt || _alt),
    );
    if (usesToggledModifier) {
      clearModifiers();
    }
    return result;
  }
}

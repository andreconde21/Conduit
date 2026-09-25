import 'package:conduit/features/app_lock/domain/app_authenticator.dart';
import 'package:flutter/foundation.dart';

enum AppLockStatus { locked, checking, unlocked, unavailable }

class AppLockController extends ChangeNotifier {
  /// [enabled] false (a platform without device authentication, see
  /// `PlatformFeatures.appLock`) starts unlocked and never locks, instead of
  /// greeting every launch with "Continue without auth".
  AppLockController(this._authenticator, {this.enabled = true})
    : _status = enabled ? AppLockStatus.locked : AppLockStatus.unlocked;

  final AppAuthenticator _authenticator;
  final bool enabled;

  AppLockStatus _status;
  String? _message;

  AppLockStatus get status => _status;
  String? get message => _message;
  bool get isUnlocked => _status == AppLockStatus.unlocked;

  Future<void> unlock() async {
    if (_status == AppLockStatus.checking) {
      return;
    }

    _status = AppLockStatus.checking;
    _message = null;
    notifyListeners();

    final canAuthenticate = await _canAuthenticate();
    if (!canAuthenticate) {
      _status = AppLockStatus.unavailable;
      _message =
          'Device authentication is not configured. '
          'Set a screen lock to keep saved hosts private.';
      notifyListeners();
      return;
    }

    final result = await _authenticate();
    switch (result) {
      case AppAuthenticationResult.success:
        _status = AppLockStatus.unlocked;
        _message = null;
      case AppAuthenticationResult.cancelled:
        _status = AppLockStatus.locked;
        _message = 'Authentication was cancelled.';
      case AppAuthenticationResult.unavailable:
        _status = AppLockStatus.unavailable;
        _message =
            'Device authentication is unavailable on this device. '
            'Set a screen lock for better protection.';
    }
    notifyListeners();
  }

  Future<bool> _canAuthenticate() async {
    try {
      return await _authenticator.canAuthenticate();
    } catch (_) {
      return false;
    }
  }

  Future<AppAuthenticationResult> _authenticate() async {
    try {
      return await _authenticator.authenticate();
    } catch (_) {
      return AppAuthenticationResult.cancelled;
    }
  }

  void continueWithoutAuth() {
    if (_status != AppLockStatus.unavailable) {
      return;
    }
    _status = AppLockStatus.unlocked;
    notifyListeners();
  }

  void lock() {
    if (!enabled) return;
    _status = AppLockStatus.locked;
    _message = null;
    notifyListeners();
  }
}

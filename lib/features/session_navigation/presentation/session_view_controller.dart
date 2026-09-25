import 'dart:async';

import 'package:conduit/features/session_navigation/domain/session_view_preferences.dart';
import 'package:flutter/widgets.dart';

/// The "Open Claude sessions in" setting and the per-session overrides,
/// loaded once and saved on every change.
class SessionViewController extends ChangeNotifier {
  SessionViewController(this._repository);

  final SessionViewPreferencesRepository _repository;
  SessionViewPreferences _preferences = const SessionViewPreferences();
  Future<void>? _loading;
  bool _disposed = false;

  SessionViewPreferences get preferences => _preferences;

  SessionView get defaultView => _preferences.defaultView;

  /// The override of [sessionHostId], or null when it follows the default.
  SessionView? overrideFor(String sessionHostId) =>
      _preferences.overrideFor(sessionHostId);

  /// See [SessionViewPreferences.resolve].
  SessionView viewFor(String sessionHostId, {required bool runsClaude}) =>
      _preferences.resolve(sessionHostId, runsClaude: runsClaude);

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final loaded = await _repository.load();
    if (_disposed) return;
    // A change made before the load finished wins over the stored value.
    if (_preferences == const SessionViewPreferences()) {
      _preferences = loaded;
      notifyListeners();
    }
  }

  Future<void> setDefaultView(SessionView view) =>
      _update(_preferences.copyWith(defaultView: view));

  /// Sets [sessionHostId]'s override; null makes it follow the default.
  Future<void> setOverride(String sessionHostId, SessionView? view) =>
      _update(_preferences.withOverride(sessionHostId, view));

  Future<void> _update(SessionViewPreferences next) async {
    if (next == _preferences || _disposed) return;
    _preferences = next;
    notifyListeners();
    await _repository.save(next);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Makes the [SessionViewController] reachable from every page and sheet.
class SessionViewScope extends InheritedNotifier<SessionViewController> {
  const SessionViewScope({
    required SessionViewController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The app's controller, or null when none is installed (tests, or a
  /// build without the feature). With [listen] the caller rebuilds when a
  /// choice changes.
  static SessionViewController? maybeOf(
    BuildContext context, {
    bool listen = false,
  }) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<SessionViewScope>()
        : context.getInheritedWidgetOfExactType<SessionViewScope>();
    return scope?.notifier;
  }
}

/// Starts loading [controller] without waiting for it.
void loadSessionViews(SessionViewController controller) =>
    unawaited(controller.load());

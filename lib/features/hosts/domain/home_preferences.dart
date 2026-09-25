import 'package:flutter/foundation.dart';

/// How the home page lays out open sessions.
enum HomeSessionsView {
  /// Live preview tiles, two columns on a phone.
  grid,

  /// Live preview tiles, one column on a phone.
  large,

  /// Compact rows.
  list,
}

/// How the home page lays out the other (not open) workspaces.
enum HomeWorkspacesView { grid, list }

/// The home page's remembered choices.
@immutable
class HomePreferences {
  const HomePreferences({
    this.machineFilter = const {},
    this.sessionsView = HomeSessionsView.grid,
    this.workspacesView = HomeWorkspacesView.grid,
  });

  factory HomePreferences.fromJson(Object? json) {
    if (json is! Map) return const HomePreferences();
    final filter = json['machineFilter'];
    return HomePreferences(
      machineFilter: filter is List ? filter.whereType<String>().toSet() : {},
      sessionsView:
          HomeSessionsView.values
              .where((value) => value.name == json['sessionsView'])
              .firstOrNull ??
          HomeSessionsView.grid,
      workspacesView:
          HomeWorkspacesView.values
              .where((value) => value.name == json['workspacesView'])
              .firstOrNull ??
          HomeWorkspacesView.grid,
    );
  }

  /// Keys of the machines the page is filtered to (saved host ids, and
  /// `local:<instance>` for local shells); empty means every machine.
  final Set<String> machineFilter;
  final HomeSessionsView sessionsView;
  final HomeWorkspacesView workspacesView;

  HomePreferences copyWith({
    Set<String>? machineFilter,
    HomeSessionsView? sessionsView,
    HomeWorkspacesView? workspacesView,
  }) {
    return HomePreferences(
      machineFilter: machineFilter ?? this.machineFilter,
      sessionsView: sessionsView ?? this.sessionsView,
      workspacesView: workspacesView ?? this.workspacesView,
    );
  }

  Map<String, Object?> toJson() => {
    'machineFilter': machineFilter.toList()..sort(),
    'sessionsView': sessionsView.name,
    'workspacesView': workspacesView.name,
  };

  @override
  bool operator ==(Object other) =>
      other is HomePreferences &&
      setEquals(other.machineFilter, machineFilter) &&
      other.sessionsView == sessionsView &&
      other.workspacesView == workspacesView;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(machineFilter),
    sessionsView,
    workspacesView,
  );
}

/// Where [HomePreferences] are kept.
abstract interface class HomePreferencesRepository {
  Future<HomePreferences> load();

  Future<void> save(HomePreferences preferences);
}

/// Keeps preferences for the app's lifetime only (tests, previews).
class InMemoryHomePreferencesRepository implements HomePreferencesRepository {
  InMemoryHomePreferencesRepository([this.stored = const HomePreferences()]);

  HomePreferences stored;
  int saves = 0;

  @override
  Future<HomePreferences> load() async => stored;

  @override
  Future<void> save(HomePreferences preferences) async {
    stored = preferences;
    saves += 1;
  }
}

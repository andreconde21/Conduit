import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips through JSON', () {
    const preferences = HomePreferences(
      machineFilter: {'b', 'a', 'local:dev'},
      sessionsView: HomeSessionsView.list,
      workspacesView: HomeWorkspacesView.list,
    );
    final json = preferences.toJson();
    expect(json['machineFilter'], ['a', 'b', 'local:dev']);
    expect(HomePreferences.fromJson(json), preferences);
  });

  test('unknown or missing values fall back to the defaults', () {
    expect(HomePreferences.fromJson(null), const HomePreferences());
    expect(
      HomePreferences.fromJson({
        'machineFilter': ['a', 3],
        'sessionsView': 'mosaic',
      }),
      const HomePreferences(machineFilter: {'a'}),
    );
  });
}

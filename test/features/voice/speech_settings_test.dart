import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  test('speech language persists through the preferences repository', () async {
    final storage = InMemorySecureStorage();
    final repository = ThemePreferencesRepository(storage);
    final controller = ThemeController(repository);
    await controller.load();
    expect(controller.speechLanguage, '');

    await controller.setSpeechLanguage(' pt-PT ');

    expect(controller.speechLanguage, 'pt-PT');
    final reloaded = ThemeController(repository);
    await reloaded.load();
    expect(reloaded.speechLanguage, 'pt-PT');
  });
}

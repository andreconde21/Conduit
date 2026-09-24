import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  test('shareInboxDirectory round-trips through JSON', () {
    final host = buildHost('a').copyWith(shareInboxDirectory: ' ~/drop ');

    final decoded = SavedHost.fromJson(host.toJson());

    expect(decoded.shareInboxDirectory, '~/drop');
  });

  test('hosts saved before the setting default to an empty inbox', () {
    final json = buildHost('a').toJson()..remove('shareInboxDirectory');

    expect(SavedHost.fromJson(json).shareInboxDirectory, isEmpty);
  });
}

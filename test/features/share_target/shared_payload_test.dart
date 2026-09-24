import 'package:conduit/features/share_target/domain/shared_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SharedPayload.fromMap', () {
    test('parses text, subject and files from the bridge map', () {
      final payload = SharedPayload.fromMap({
        'text': '  Look at this  ',
        'subject': 'A subject',
        'files': [
          {
            'path': '/cache/shared/1/photo.jpg',
            'name': 'photo.jpg',
            'size': 1234,
            'mimeType': 'image/jpeg',
          },
        ],
      });

      expect(payload, isNotNull);
      expect(payload!.text, 'Look at this');
      expect(payload.subject, 'A subject');
      expect(payload.files, hasLength(1));
      expect(payload.files.single.path, '/cache/shared/1/photo.jpg');
      expect(payload.files.single.name, 'photo.jpg');
      expect(payload.files.single.size, 1234);
      expect(payload.files.single.mimeType, 'image/jpeg');
      expect(payload.summary, 'photo.jpg and text');
    });

    test('drops malformed files and falls back to the path basename', () {
      final payload = SharedPayload.fromMap({
        'files': [
          {'path': '/cache/shared/2/report.pdf', 'size': 10.0},
          {'name': 'no-path.txt'},
          'garbage',
          {'path': ''},
        ],
      });

      expect(payload, isNotNull);
      expect(payload!.hasText, isFalse);
      expect(payload.files.map((f) => f.name), ['report.pdf']);
      expect(payload.files.single.size, 10);
      expect(payload.files.single.mimeType, isNull);
    });

    test('returns null when nothing usable was shared', () {
      expect(
        SharedPayload.fromMap({'text': '   ', 'files': <Object?>[]}),
        isNull,
      );
      expect(SharedPayload.fromMap({'text': null}), isNull);
      expect(SharedPayload.fromMap('not a map'), isNull);
      expect(SharedPayload.fromMap(null), isNull);
    });

    test('summarizes multiple files', () {
      final payload = SharedPayload.fromMap({
        'files': [
          {'path': '/a/one.png', 'name': 'one.png'},
          {'path': '/a/two.png', 'name': 'two.png'},
        ],
      });

      expect(payload!.summary, '2 files');
    });
  });
}

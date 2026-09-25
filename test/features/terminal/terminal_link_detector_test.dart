import 'package:conduit/features/terminal/domain/terminal_link_detector.dart';
import 'package:conduit/features/terminal/domain/terminal_path_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('terminalUrlAt', () {
    test('finds the link under the tapped column', () {
      const line = 'Visit https://example.com/a/b?x=1#top for docs';
      for (final part in ['https', 'example', '/b?x', '#top']) {
        expect(
          terminalUrlAt(line, line.indexOf(part)),
          'https://example.com/a/b?x=1#top',
        );
      }
      expect(terminalUrlAt(line, line.indexOf('Visit')), isNull);
      expect(terminalUrlAt(line, line.indexOf(' for')), isNull);
    });

    test('drops sentence punctuation and quotes around the link', () {
      const dot = 'Open http://localhost:3000/.';
      expect(terminalUrlAt(dot, 8), 'http://localhost:3000/');
      const quoted = 'url: "https://a.dev/x", next';
      expect(terminalUrlAt(quoted, quoted.indexOf('a.dev')), 'https://a.dev/x');
      const single = "at 'https://a.dev/y'";
      expect(terminalUrlAt(single, single.indexOf('a.dev')), 'https://a.dev/y');
    });

    test('keeps balanced parentheses and drops a wrapping one', () {
      const wiki = 'see https://en.wikipedia.org/wiki/Dart_(language) ok';
      expect(
        terminalUrlAt(wiki, wiki.indexOf('wiki')),
        'https://en.wikipedia.org/wiki/Dart_(language)',
      );
      const wrapped = '(docs: https://dart.dev/guides)';
      expect(
        terminalUrlAt(wrapped, wrapped.indexOf('dart')),
        'https://dart.dev/guides',
      );
      const markdown = '[link](https://dart.dev)';
      expect(
        terminalUrlAt(markdown, markdown.indexOf('dart')),
        'https://dart.dev',
      );
    });

    test('stops at TUI borders and ignores other schemes', () {
      const boxed = '│ https://claude.ai/oauth?code=abc │';
      expect(
        terminalUrlAt(boxed, boxed.indexOf('claude')),
        'https://claude.ai/oauth?code=abc',
      );
      const ftp = 'ftp://example.com/file';
      expect(terminalUrlAt(ftp, 8), isNull);
      expect(terminalUrlAt('https:// nothing', 2), isNull);
    });

    test('accepts an upper-case scheme and handles bad columns', () {
      expect(terminalUrlAt('HTTPS://A.DEV', 3), 'HTTPS://A.DEV');
      expect(terminalUrlAt('https://a.dev', -1), isNull);
      expect(terminalUrlAt('https://a.dev', 99), isNull);
      expect(terminalUrlAt('', 0), isNull);
    });

    test('picks the right link among several', () {
      const line = 'a https://one.dev b https://two.dev/c';
      expect(terminalUrlAt(line, line.indexOf('two')), 'https://two.dev/c');
      expect(terminalUrlsIn(line), ['https://one.dev', 'https://two.dev/c']);
    });

    test('the path detector keeps rejecting links', () {
      const line = 'open https://example.com/a/b now';
      expect(terminalPathAt(line, line.indexOf('example')), isNull);
    });
  });

  group('loopbackPreviewPort', () {
    test('returns the port of links to the host itself over http', () {
      expect(loopbackPreviewPort('http://localhost:5173/'), 5173);
      expect(loopbackPreviewPort('http://127.0.0.1:8000/api'), 8000);
      expect(loopbackPreviewPort('http://0.0.0.0:3000'), 3000);
      expect(loopbackPreviewPort('http://[::1]:4000/x'), 4000);
    });

    test('is null for other hosts, https and implicit ports', () {
      expect(loopbackPreviewPort('http://example.com:3000/'), isNull);
      expect(loopbackPreviewPort('https://localhost:3000/'), isNull);
      expect(loopbackPreviewPort('http://localhost/'), isNull);
    });

    test('previewPathOf keeps path and query', () {
      expect(previewPathOf('http://localhost:3000'), '/');
      expect(previewPathOf('http://localhost:3000/a/b?c=1'), '/a/b?c=1');
    });
  });
}

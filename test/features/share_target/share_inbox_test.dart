import 'package:conduit/features/share_target/domain/share_inbox.dart';
import 'package:conduit/features/share_target/domain/shared_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveShareInboxPath', () {
    const home = '/home/andre';

    test('defaults to ~/conductore-inbox', () {
      expect(
        resolveShareInboxPath(configured: '', home: home),
        '/home/andre/conductore-inbox',
      );
      expect(
        resolveShareInboxPath(configured: '   ', home: home),
        '/home/andre/conductore-inbox',
      );
    });

    test('expands ~ against the resolved home directory', () {
      expect(
        resolveShareInboxPath(configured: '~/inbox/', home: home),
        '/home/andre/inbox',
      );
      expect(resolveShareInboxPath(configured: '~', home: home), home);
    });

    test('keeps absolute paths and anchors relative ones under home', () {
      expect(
        resolveShareInboxPath(configured: '/srv/drop//', home: home),
        '/srv/drop',
      );
      expect(
        resolveShareInboxPath(configured: 'projects/in', home: home),
        '/home/andre/projects/in',
      );
    });

    test('copes with a root home directory', () {
      expect(
        resolveShareInboxPath(configured: '', home: '/'),
        '/conductore-inbox',
      );
      expect(resolveShareInboxPath(configured: '~/x', home: '/'), '/x');
    });
  });

  group('file names', () {
    test('sanitizes separators, control characters and dot prefixes', () {
      expect(sanitizeShareFileName('../etc/passwd'), '_etc_passwd');
      expect(sanitizeShareFileName('bad\nname.txt'), 'bad_name.txt');
      expect(sanitizeShareFileName('  spaced   out.png '), 'spaced out.png');
      expect(sanitizeShareFileName('...'), 'shared');
    });

    test('avoids collisions with a counter before the extension', () {
      expect(uniqueShareFileName('photo.jpg', {}), 'photo.jpg');
      expect(uniqueShareFileName('photo.jpg', {'photo.jpg'}), 'photo (2).jpg');
      expect(
        uniqueShareFileName('photo.jpg', {'photo.jpg', 'photo (2).jpg'}),
        'photo (3).jpg',
      );
      expect(uniqueShareFileName('README', {'README'}), 'README (2)');
    });

    test('plans unique names across the batch and the inbox listing', () {
      final names = planShareFileNames(
        const [
          SharedFile(path: '/c/1/a.png', name: 'a.png'),
          SharedFile(path: '/c/2/a.png', name: 'a.png'),
          SharedFile(path: '/c/3/b.png', name: 'b.png'),
        ],
        {'b.png'},
      );

      expect(names, ['a.png', 'a (2).png', 'b (2).png']);
    });

    test('joins the inbox and the file name', () {
      expect(shareRemotePath('/home/a/inbox', 'x.txt'), '/home/a/inbox/x.txt');
      expect(shareRemotePath('/', 'x.txt'), '/x.txt');
    });
  });

  group('drafts', () {
    test('lists shared text then one remote path per line', () {
      expect(
        buildShareDraft(
          text: ' Please review ',
          remotePaths: ['/home/a/inbox/one.png', '/home/a/inbox/two.pdf'],
        ),
        'Please review\n\n/home/a/inbox/one.png\n/home/a/inbox/two.pdf',
      );
      expect(buildShareDraft(text: 'only text'), 'only text');
      expect(buildShareDraft(remotePaths: ['/p']), '/p');
      expect(buildShareDraft(), '');
    });

    test('appends to an existing composer draft', () {
      expect(mergeShareDraft('', '/p'), '/p');
      expect(mergeShareDraft('   ', '/p'), '/p');
      expect(mergeShareDraft('typed', ''), 'typed');
      expect(mergeShareDraft('typed', '/p'), 'typed\n\n/p');
      expect(mergeShareDraft('typed\n', '/p'), 'typed\n\n/p');
    });
  });
}

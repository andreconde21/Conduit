import 'package:conduit/features/sftp/presentation/sftp_browser_controller.dart';
import 'package:conduit/features/sftp/presentation/widgets/sftp_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const longBookmark =
      '/var/lib/docker/volumes/very-long-project-name_data/_data/releases';

  Widget build({
    required List<String> bookmarks,
    required bool isBookmarked,
    VoidCallback? onToggleBookmark,
    ValueChanged<String>? onOpenBookmark,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SftpHeader(
          hostName: 'dev',
          path: '/var/lib/docker/volumes/very-long-project-name_data/_data',
          busy: false,
          searchController: TextEditingController(),
          searchQuery: '',
          sortMode: SftpSortMode.name,
          totalCount: 3,
          visibleCount: 3,
          directoryCount: 1,
          fileCount: 2,
          onBack: () {},
          onSegmentTap: (_) {},
          onSearchChanged: (_) {},
          onClearSearch: () {},
          onSortChanged: (_) {},
          onRefresh: () {},
          bookmarks: bookmarks,
          isBookmarked: isBookmarked,
          onToggleBookmark: onToggleBookmark,
          onOpenBookmark: onOpenBookmark ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('bookmark menu lists long paths on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? opened;

    await tester.pumpWidget(
      build(
        bookmarks: const [longBookmark, '/etc'],
        isBookmarked: false,
        onOpenBookmark: (path) => opened = path,
      ),
    );
    await tester.tap(find.byTooltip('Bookmarked folders'));
    await tester.pumpAndSettle();

    expect(find.text(longBookmark), findsOneWidget);
    expect(find.text('/etc'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('/etc'));
    await tester.pumpAndSettle();

    expect(opened, '/etc');
  });

  testWidgets('empty bookmark menu shows a disabled hint', (tester) async {
    await tester.pumpWidget(build(bookmarks: const [], isBookmarked: false));
    await tester.tap(find.byTooltip('Bookmarked folders'));
    await tester.pumpAndSettle();

    expect(find.text('No bookmarks yet'), findsOneWidget);
  });

  testWidgets('star reflects and toggles the bookmark state', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(
      build(
        bookmarks: const ['/etc'],
        isBookmarked: true,
        onToggleBookmark: () => toggles++,
      ),
    );

    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Remove bookmark'));
    expect(toggles, 1);

    await tester.pumpWidget(build(bookmarks: const [], isBookmarked: false));
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Bookmark this folder'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}

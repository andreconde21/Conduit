import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_controller.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'live_preview_controller_test.dart' show FakePortForwarder;
import 'live_preview_view_test.dart' show FakeWebViewPlatform;

/// Linux and Windows have no webview_flutter implementation: the forward
/// still runs and the page opens in the system browser.
void main() {
  testWidgets(
    'without an embedded web view the preview offers the browser',
    (tester) async {
      final platform = FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      final controller = LivePreviewController(
        FakePortForwarder(),
        hostId: 'h',
      );
      addTearDown(controller.dispose);
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LivePreviewView(
              controller: controller,
              palette: AppPalette.catppuccin,
              brightness: Brightness.dark,
              onChangePort: () {},
              openExternal: (url) async {
                opened.add(url);
                return true;
              },
            ),
          ),
        ),
      );
      await controller.start(3000);
      await tester.pump();

      expect(platform.controller, isNull);
      expect(find.byKey(const Key('webview')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Open in browser'));
      await tester.pump();
      expect(opened, [Uri.parse('http://127.0.0.1:40000/')]);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );
}

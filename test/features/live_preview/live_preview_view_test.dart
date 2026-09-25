import 'dart:async';

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_controller.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'live_preview_controller_test.dart'
    show FakePortForwarder;

/// Records what the page asks of the platform WebView.
class FakeWebViewPlatform extends WebViewPlatform {
  FakeWebViewController? controller;
  FakeNavigationDelegate? navigation;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = FakeWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => navigation = FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWebViewWidget(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => throw UnimplementedError();
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  final List<Uri> loaded = [];
  int reloads = 0;
  JavaScriptMode? javaScriptMode;

  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      loaded.add(params.uri);

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async =>
      javaScriptMode = mode;

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  UrlChangeCallback? onUrlChange;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async => this.onNavigationRequest = onNavigationRequest;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async =>
      this.onPageStarted = onPageStarted;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async =>
      this.onPageFinished = onPageFinished;

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async =>
      this.onUrlChange = onUrlChange;

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async => this.onWebResourceError = onWebResourceError;

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {}
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const Placeholder(key: Key('webview'));
}

class FakeWebResourceError extends WebResourceError {
  const FakeWebResourceError()
    : super(errorCode: -6, description: 'net::ERR_CONNECTION_REFUSED', isForMainFrame: true);
}

void main() {
  late FakeWebViewPlatform platform;
  late FakePortForwarder forwarder;
  late LivePreviewController controller;
  final external = <Uri>[];
  var changePortTaps = 0;

  setUp(() {
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    forwarder = FakePortForwarder();
    controller = LivePreviewController(forwarder, hostId: 'h');
    external.clear();
    changePortTaps = 0;
  });

  tearDown(() => controller.dispose());

  Widget app() => MaterialApp(
    home: Scaffold(
      body: LivePreviewView(
        controller: controller,
        palette: AppPalette.catppuccin,
        brightness: Brightness.dark,
        onChangePort: () => changePortTaps++,
        openExternal: (url) async {
          external.add(url);
          return true;
        },
      ),
    ),
  );

  testWidgets('shows a spinner while connecting, then loads the forward URL', (tester) async {
    forwarder.gate = Completer<void>();
    await tester.pumpWidget(app());
    final starting = controller.start(3000);
    await tester.pump();
    expect(find.textContaining('Forwarding port 3000'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    forwarder.gate!.complete();
    await starting;
    await tester.pump();
    expect(find.byKey(const Key('webview')), findsOneWidget);
    expect(platform.controller!.loaded, [Uri.parse('http://127.0.0.1:40000/')]);
    expect(platform.controller!.javaScriptMode, JavaScriptMode.unrestricted);
    expect(find.text(':3000'), findsOneWidget);
  });

  testWidgets('the address bar navigates within the forward', (tester) async {
    await tester.pumpWidget(app());
    await controller.start(3000);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'admin?tab=1');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(platform.controller!.loaded.last, Uri.parse('http://127.0.0.1:40000/admin?tab=1'));
    expect(find.text('/admin?tab=1'), findsOneWidget);
  });

  testWidgets('page navigation updates the address bar; foreign links open outside', (tester) async {
    await tester.pumpWidget(app());
    await controller.start(3000);
    await tester.pump();
    final navigation = platform.navigation!;
    navigation.onUrlChange!(const UrlChange(url: 'http://127.0.0.1:40000/docs'));
    await tester.pump();
    expect(controller.path, '/docs');
    expect(find.text('/docs'), findsOneWidget);

    final inside = navigation.onNavigationRequest!(
      const NavigationRequest(url: 'http://127.0.0.1:40000/x', isMainFrame: true),
    );
    expect(await inside, NavigationDecision.navigate);
    final outside = navigation.onNavigationRequest!(
      const NavigationRequest(url: 'https://example.com/', isMainFrame: true),
    );
    expect(await outside, NavigationDecision.prevent);
    expect(external, [Uri.parse('https://example.com/')]);
  });

  testWidgets('reload and open-in-browser act on the current URL', (tester) async {
    await tester.pumpWidget(app());
    await controller.start(3000);
    await tester.pump();
    await tester.tap(find.byTooltip('Reload'));
    await tester.pump();
    expect(platform.controller!.reloads, 1);
    await tester.tap(find.byTooltip('Open in browser'));
    await tester.pump();
    expect(external, [Uri.parse('http://127.0.0.1:40000/')]);
  });

  testWidgets('a forward failure shows the message with retry and change port', (tester) async {
    forwarder.refused.add(3000);
    await tester.pumpWidget(app());
    await controller.start(3000);
    await tester.pump();
    expect(find.text('Could not open the preview'), findsOneWidget);
    expect(find.text('Nothing is listening on port 3000 on Host h.'), findsOneWidget);
    expect(find.byKey(const Key('webview')), findsNothing);
    await tester.tap(find.text('Change port'));
    expect(changePortTaps, 1);
    forwarder.refused.clear();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('webview')), findsOneWidget);
  });

  testWidgets('a restart on a new local port reloads the WebView', (tester) async {
    await tester.pumpWidget(app());
    await controller.start(3000);
    await tester.pump();
    await controller.start(8080);
    await tester.pump();
    expect(platform.controller!.loaded, [
      Uri.parse('http://127.0.0.1:40000/'),
      Uri.parse('http://127.0.0.1:40001/'),
    ]);
    expect(find.text(':8080'), findsOneWidget);
  });

  testWidgets('a closed forward offers to reconnect', (tester) async {
    await tester.pumpWidget(app());
    await controller.start(3000);
    await tester.pump();
    await controller.stop(reason: 'The session disconnected.');
    await tester.pump();
    expect(find.text('Preview closed'), findsOneWidget);
    expect(find.text('The session disconnected.'), findsOneWidget);
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    await tester.pump();
    expect(controller.phase, LivePreviewPhase.ready);
  });

  testWidgets('tunnelled connection errors show a banner', (tester) async {
    await tester.pumpWidget(app());
    await controller.start(3000);
    await tester.pump();
    forwarder.opened.single.errors.add(
      'Port 3000 refused the connection.',
    );
    await tester.pump();
    expect(find.text('Port 3000 refused the connection.'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(find.text('Port 3000 refused the connection.'), findsNothing);
  });

  testWidgets('a main-frame load error replaces the page with a notice', (tester) async {
    await tester.pumpWidget(app());
    await controller.start(3000);
    await tester.pump();
    platform.navigation!.onWebResourceError!(const FakeWebResourceError());
    await tester.pump();
    expect(find.text('The page did not load'), findsOneWidget);
    expect(find.text('net::ERR_CONNECTION_REFUSED'), findsOneWidget);
    await tester.tap(find.text('Reload'));
    await tester.pump();
    expect(platform.controller!.reloads, 1);
    expect(find.byKey(const Key('webview')), findsOneWidget);
  });
}

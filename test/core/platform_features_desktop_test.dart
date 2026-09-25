import 'package:conduit/core/platform_features.dart';
import 'package:conduit/core/presentation/desktop_layout.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_doubles.dart';

void main() {
  const desktops = {
    TargetPlatform.linux,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  };

  testWidgets(
    'desktop hides Android-only features and the touch key rows',
    (tester) async {
      expect(PlatformFeatures.isDesktop, isTrue);
      expect(PlatformFeatures.dictation, isFalse);
      expect(PlatformFeatures.shareTarget, isFalse);
      expect(PlatformFeatures.agentNotifications, isFalse);
      expect(PlatformFeatures.homeWidget, isFalse);
      expect(PlatformFeatures.clipboardImage, isFalse);
      expect(PlatformFeatures.backgroundKeepalive, isFalse);
      expect(PlatformFeatures.prootLocalShell, isFalse);
      expect(PlatformFeatures.hardwareSecurityKeys, isFalse);
      expect(PlatformFeatures.camera, isFalse);
      expect(PlatformFeatures.touchKeyRowsByDefault, isFalse);
    },
    variant: const TargetPlatformVariant(desktops),
  );

  testWidgets(
    'embedded web view only where webview_flutter has an implementation',
    (tester) async {
      expect(
        PlatformFeatures.embeddedWebView,
        defaultTargetPlatform == TargetPlatform.macOS,
      );
    },
    variant: const TargetPlatformVariant(desktops),
  );

  testWidgets(
    'app lock is unavailable only on Linux',
    (tester) async {
      expect(
        PlatformFeatures.appLock,
        defaultTargetPlatform != TargetPlatform.linux,
      );
    },
    variant: const TargetPlatformVariant(desktops),
  );

  test('phones keep every feature and the key rows', () {
    // flutter_test runs as Android by default.
    expect(PlatformFeatures.isDesktop, isFalse);
    expect(PlatformFeatures.dictation, isTrue);
    expect(PlatformFeatures.hardwareSecurityKeys, isTrue);
    expect(PlatformFeatures.embeddedWebView, isTrue);
    expect(PlatformFeatures.appLock, isTrue);
    expect(PlatformFeatures.camera, isTrue);
    expect(PlatformFeatures.touchKeyRowsByDefault, isTrue);
  });

  test('a disabled app lock starts unlocked and never locks', () {
    final controller = AppLockController(
      UnavailableAuthenticator(),
      enabled: false,
    );
    expect(controller.isUnlocked, isTrue);
    controller.lock();
    expect(controller.isUnlocked, isTrue);
  });

  testWidgets(
    'the home content is centred at a max width on desktop',
    (tester) async {
      expect(desktopSideInset(800), 0);
      expect(desktopSideInset(desktopContentMaxWidth + 400), 200);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  test('phones and tablets keep the full width', () {
    expect(desktopSideInset(1400), 0);
  });
}

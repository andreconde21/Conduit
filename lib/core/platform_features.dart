import 'package:flutter/foundation.dart';

/// Features backed by Conductore's own Android platform channels
/// (MainActivity and friends). iOS has no native side for them, so the UI
/// hides them there instead of offering controls that silently do nothing.
///
/// Every getter reads [defaultTargetPlatform], so widget tests (which run as
/// Android by default) keep exercising the Android UI, and a test can flip
/// `debugDefaultTargetPlatformOverride` to check the iOS layout.
abstract final class PlatformFeatures {
  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  /// On-device dictation (`conduit/speech`).
  static bool get dictation => _android;

  /// On-device text-to-speech for Chat View replies (`conduit/tts`).
  static bool get textToSpeech => _android;

  /// Receiving text and files from the system share sheet
  /// (`conduit/share_target`).
  static bool get shareTarget => _android;

  /// Agent notifications with Allow / Deny actions
  /// (`conduit/agent_notifications`).
  static bool get agentNotifications => _android;

  /// Home screen widget and Quick Settings tile
  /// (`conduit/agent_status_widget`).
  static bool get homeWidget => _android;

  /// Pasting an image from the clipboard into a prompt
  /// (`conduit/clipboard_image`).
  static bool get clipboardImage => _android;

  /// Foreground service that keeps sessions alive in the background
  /// (`conduit/background_keepalive`).
  static bool get backgroundKeepalive => _android;
}

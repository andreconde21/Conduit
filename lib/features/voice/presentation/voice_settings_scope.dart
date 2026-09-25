import 'package:conduit/core/theme/theme_controller.dart';
import 'package:flutter/widgets.dart';

/// Makes the app settings reachable from voice widgets deep in routes
/// (Chat View's read-aloud toggle, the mic button's continuous mode)
/// without threading them through every page that opens a chat.
///
/// Readers look values up when they act, so the scope never rebuilds its
/// subtree when a setting changes.
class VoiceSettingsScope extends InheritedWidget {
  const VoiceSettingsScope({
    required this.settings,
    required super.child,
    super.key,
  });

  final ThemeController settings;

  static ThemeController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<VoiceSettingsScope>()?.settings;

  @override
  bool updateShouldNotify(VoiceSettingsScope oldWidget) =>
      settings != oldWidget.settings;
}

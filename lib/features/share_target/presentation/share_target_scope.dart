import 'package:conduit/features/share_target/presentation/share_target_controller.dart';
import 'package:flutter/widgets.dart';

/// Makes the [ShareTargetController] reachable from any route (it sits
/// above the app's Navigator), so the terminal page can pick up drafts
/// without every page constructor threading it through.
class ShareTargetScope extends InheritedWidget {
  const ShareTargetScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final ShareTargetController controller;

  static ShareTargetController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ShareTargetScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(ShareTargetScope oldWidget) =>
      controller != oldWidget.controller;
}

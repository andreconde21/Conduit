import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ctrl+K (Cmd+K on a Mac keyboard) on a hardware keyboard: the quick
/// switcher's shortcut.
bool isQuickSwitcherShortcut(KeyEvent event) {
  if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.keyK) {
    return false;
  }
  final keyboard = HardwareKeyboard.instance;
  return (keyboard.isControlPressed || keyboard.isMetaPressed) &&
      !keyboard.isAltPressed &&
      !keyboard.isShiftPressed;
}

/// Runs [onInvoke] on Ctrl+K while this page is the top route. It listens
/// to the hardware keyboard directly, so it works whatever has the focus
/// (or nothing). A focused terminal still sees the key too: the terminal
/// page also keeps it from the session (see [isQuickSwitcherShortcut]).
class QuickSwitcherShortcut extends StatefulWidget {
  const QuickSwitcherShortcut({
    required this.onInvoke,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final VoidCallback onInvoke;
  final bool enabled;
  final Widget child;

  @override
  State<QuickSwitcherShortcut> createState() => _QuickSwitcherShortcutState();
}

class _QuickSwitcherShortcutState extends State<QuickSwitcherShortcut> {
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handle);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handle);
    super.dispose();
  }

  bool _handle(KeyEvent event) {
    if (!mounted ||
        !widget.enabled ||
        event is! KeyDownEvent ||
        !isQuickSwitcherShortcut(event)) {
      return false;
    }
    final route = _route;
    if (route != null && !route.isCurrent) return false;
    widget.onInvoke();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'package:conduit/features/live_preview/presentation/live_preview_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_file_tabs_controller.dart';
import 'package:flutter/material.dart';

/// A forwarded web app from a host, as a workspace tab. One per host; the
/// port can be changed from inside the view.
class LivePreviewTab extends TerminalFileTab {
  LivePreviewTab({required super.host, required this.controller})
    : super(path: 'live-preview');

  final LivePreviewController controller;

  @override
  String get title {
    final port = controller.remotePort;
    return port == null ? 'Preview' : 'Preview :$port';
  }

  @override
  String get tooltip => '$title · ${host.name}';

  @override
  IconData get icon => Icons.public_rounded;

  @override
  Listenable? get listenable => controller;

  @override
  bool matches(TerminalFileTab other) =>
      other is LivePreviewTab && other.host.id == host.id;

  @override
  void dispose() {
    controller.dispose();
  }
}

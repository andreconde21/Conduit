import 'package:conduit/features/diff_view/presentation/diff_view_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_file_tabs_controller.dart';
import 'package:flutter/material.dart';

/// The Git diff of a host's working directory, as a workspace tab.
///
/// One per host: opening it again re-activates the existing tab. The
/// directory can be changed from inside the view, so [path] is only the
/// identity, not the current directory.
class DiffViewTab extends TerminalFileTab {
  DiffViewTab({required super.host, required this.controller})
    : super(path: 'git-diff');

  final DiffViewController controller;

  @override
  String get title {
    final path = controller.path;
    if (path.isEmpty) {
      return 'Git diff';
    }
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    return 'Diff · ${segments.isEmpty ? path : segments.last}';
  }

  @override
  String get tooltip => '$title · ${host.name}';

  @override
  IconData get icon => Icons.difference_outlined;

  @override
  Listenable? get listenable => controller;

  @override
  bool matches(TerminalFileTab other) =>
      other is DiffViewTab && other.host.id == host.id;

  @override
  void dispose() {
    controller.dispose();
  }
}

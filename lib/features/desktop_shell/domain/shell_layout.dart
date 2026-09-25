import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// Where a dragged tab lands on a pane: one of its edges splits the pane,
/// the centre shows the view in the pane itself.
enum ShellEdge { left, right, top, bottom, center }

/// A direction for moving the focus between panes (Alt+arrows).
enum ShellDirection { left, right, up, down }

/// How a split lays out its two children.
enum ShellSplitAxis {
  /// Side by side: first on the left, second on the right.
  horizontal,

  /// Stacked: first on top, second below.
  vertical,
}

/// One node of the desktop shell's split tree.
@immutable
sealed class ShellNode {
  const ShellNode();

  Map<String, Object?> toJson();

  static ShellNode? fromJson(Object? json, [int depth = 0]) {
    if (json is! Map || depth > 6) return null;
    final type = json['type'];
    if (type == 'pane') {
      final id = json['id'];
      if (id is! String || id.isEmpty) return null;
      final view = json['view'];
      return ShellPane(id, view is String && view.isNotEmpty ? view : null);
    }
    if (type == 'split') {
      final first = fromJson(json['first'], depth + 1);
      final second = fromJson(json['second'], depth + 1);
      if (first == null || second == null) return null;
      final axis = json['axis'] == 'vertical'
          ? ShellSplitAxis.vertical
          : ShellSplitAxis.horizontal;
      final ratio = json['ratio'];
      return ShellSplit(
        axis: axis,
        ratio: ShellSplit.clampRatio(ratio is num ? ratio.toDouble() : 0.5),
        first: first,
        second: second,
      );
    }
    return null;
  }
}

/// A pane: shows one view (a terminal session, Chat View, a file, a diff
/// or a live preview), or nothing yet.
@immutable
final class ShellPane extends ShellNode {
  const ShellPane(this.id, [this.view]);

  final String id;

  /// The view id (see `shell_view_id.dart`), or null for an empty pane.
  final String? view;

  ShellPane withView(String? view) => ShellPane(id, view);

  @override
  Map<String, Object?> toJson() => {'type': 'pane', 'id': id, 'view': ?view};

  @override
  bool operator ==(Object other) =>
      other is ShellPane && other.id == id && other.view == view;

  @override
  int get hashCode => Object.hash(id, view);

  @override
  String toString() => 'Pane($id, $view)';
}

/// Two nodes side by side or stacked; [ratio] is the first child's share.
@immutable
final class ShellSplit extends ShellNode {
  const ShellSplit({
    required this.axis,
    required this.first,
    required this.second,
    this.ratio = 0.5,
  });

  final ShellSplitAxis axis;
  final double ratio;
  final ShellNode first;
  final ShellNode second;

  /// Smallest share a divider leaves either side.
  static const minRatio = 0.15;

  static double clampRatio(double ratio) =>
      ratio.isNaN ? 0.5 : ratio.clamp(minRatio, 1 - minRatio);

  ShellSplit copyWith({double? ratio, ShellNode? first, ShellNode? second}) =>
      ShellSplit(
        axis: axis,
        ratio: ratio ?? this.ratio,
        first: first ?? this.first,
        second: second ?? this.second,
      );

  @override
  Map<String, Object?> toJson() => {
    'type': 'split',
    'axis': axis.name,
    'ratio': ratio,
    'first': first.toJson(),
    'second': second.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ShellSplit &&
      other.axis == axis &&
      other.ratio == ratio &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(axis, ratio, first, second);

  @override
  String toString() => 'Split(${axis.name}, $ratio, $first, $second)';
}

/// The main area's panes: a binary split tree of up to [maxPanes] panes,
/// and the focused one. Immutable: every operation returns a new layout.
///
/// Views live in at most one pane. Showing a view that sits in another
/// pane focuses that pane instead of duplicating it.
@immutable
class ShellLayout {
  const ShellLayout._(this.root, this.focusedPaneId);

  /// One pane showing [view] (or nothing).
  factory ShellLayout.single([String? view]) =>
      ShellLayout._(ShellPane('p1', view), 'p1');

  /// The most panes the main area splits into.
  static const maxPanes = 4;

  final ShellNode root;
  final String focusedPaneId;

  /// Panes in reading order (depth first, first child before second).
  List<ShellPane> get panes {
    final result = <ShellPane>[];
    void walk(ShellNode node) {
      switch (node) {
        case ShellPane():
          result.add(node);
        case ShellSplit(:final first, :final second):
          walk(first);
          walk(second);
      }
    }

    walk(root);
    return result;
  }

  bool get isSplit => root is ShellSplit;

  bool get canSplit => panes.length < maxPanes;

  ShellPane get focusedPane =>
      panes.where((pane) => pane.id == focusedPaneId).firstOrNull ??
      panes.first;

  String? get focusedView => focusedPane.view;

  /// Every view on screen.
  Set<String> get visibleViews => {
    for (final pane in panes)
      if (pane.view != null) pane.view!,
  };

  ShellPane? paneShowing(String view) =>
      panes.where((pane) => pane.view == view).firstOrNull;

  ShellLayout focus(String paneId) {
    if (paneId == focusedPaneId || panes.every((pane) => pane.id != paneId)) {
      return this;
    }
    return ShellLayout._(root, paneId);
  }

  /// Shows [view]: focuses the pane already showing it, else puts it in
  /// the focused pane.
  ShellLayout reveal(String view) {
    final showing = paneShowing(view);
    if (showing != null) return focus(showing.id);
    final target = focusedPane;
    return ShellLayout._(
      _replace(root, target.id, (_) => target.withView(view)),
      target.id,
    );
  }

  /// Shows [view] in pane [paneId] (a drop on its centre), moving it out
  /// of the pane that showed it before (which then closes).
  ShellLayout showIn(String paneId, String view) {
    final target = panes.where((pane) => pane.id == paneId).firstOrNull;
    if (target == null) return reveal(view);
    if (target.view == view) return focus(paneId);
    var layout = this;
    final previous = paneShowing(view);
    if (previous != null && previous.id != paneId) {
      layout = layout.closePane(previous.id);
    }
    return ShellLayout._(
      _replace(
        layout.root,
        paneId,
        (pane) => (pane as ShellPane).withView(view),
      ),
      paneId,
    );
  }

  /// Splits pane [paneId] at [edge] and shows [view] in the new pane,
  /// which gets the focus. [view] leaves the pane it was in (closing that
  /// pane unless it is [paneId], which then keeps [fallbackView]).
  /// [ShellEdge.center] is [showIn]. Beyond [maxPanes] the view just
  /// replaces [paneId]'s.
  ShellLayout split(
    String paneId,
    ShellEdge edge,
    String view, {
    String? fallbackView,
  }) {
    if (edge == ShellEdge.center) return showIn(paneId, view);
    var layout = this;
    final previous = paneShowing(view);
    if (previous != null && previous.id != paneId) {
      layout = layout.closePane(previous.id);
    }
    final target = layout.panes.where((pane) => pane.id == paneId).firstOrNull;
    if (target == null) return layout.reveal(view);
    if (target.view == view) {
      // Splitting a pane with its own view: the old pane keeps another.
      if (layout.panes.length == 1 && fallbackView == null) return layout;
      layout = ShellLayout._(
        _replace(layout.root, paneId, (_) => target.withView(fallbackView)),
        layout.focusedPaneId,
      );
    }
    if (!layout.canSplit) return layout.showIn(paneId, view);
    final newId = layout._nextPaneId();
    final created = ShellPane(newId, view);
    final existing = layout.panes.firstWhere((pane) => pane.id == paneId);
    final axis = edge == ShellEdge.left || edge == ShellEdge.right
        ? ShellSplitAxis.horizontal
        : ShellSplitAxis.vertical;
    final before = edge == ShellEdge.left || edge == ShellEdge.top;
    final node = ShellSplit(
      axis: axis,
      first: before ? created : existing,
      second: before ? existing : created,
    );
    return ShellLayout._(_replace(layout.root, paneId, (_) => node), newId);
  }

  /// Removes pane [paneId]; its sibling takes the space. The last pane is
  /// emptied instead.
  ShellLayout closePane(String paneId) {
    if (root is ShellPane) {
      return (root as ShellPane).id == paneId
          ? ShellLayout._((root as ShellPane).withView(null), focusedPaneId)
          : this;
    }
    ShellNode? remove(ShellNode node) {
      switch (node) {
        case ShellPane(:final id):
          return id == paneId ? null : node;
        case ShellSplit(:final first, :final second):
          final a = remove(first);
          final b = remove(second);
          if (a == null) return b;
          if (b == null) return a;
          if (identical(a, first) && identical(b, second)) return node;
          return node.copyWith(first: a, second: b);
      }
    }

    final next = remove(root);
    if (next == null) return this;
    final layout = ShellLayout._(next, focusedPaneId);
    if (layout.panes.any((pane) => pane.id == focusedPaneId)) return layout;
    // The focus goes to the pane that took the closed one's place.
    final before = panes.indexWhere((pane) => pane.id == paneId);
    final remaining = layout.panes;
    final index = math.min(math.max(before, 0), remaining.length - 1);
    return ShellLayout._(next, remaining[index].id);
  }

  /// [view] went away (its session or tab closed): its pane closes, or
  /// shows [replacement] when it is the only pane.
  ShellLayout removeView(String view, {String? replacement}) {
    final pane = paneShowing(view);
    if (pane == null) return this;
    if (panes.length > 1) return closePane(pane.id);
    return ShellLayout._(
      _replace(root, pane.id, (_) => pane.withView(replacement)),
      focusedPaneId,
    );
  }

  /// Only the views in [existing] stay: panes whose view is gone close
  /// (the last pane is emptied). Used when rendering a layout restored
  /// before its sessions came back, and before every edit.
  ShellLayout pruned(Set<String> existing) {
    var layout = this;
    for (final pane in panes) {
      final view = pane.view;
      if (view == null && layout.panes.length > 1) {
        layout = layout.closePane(pane.id);
      } else if (view != null && !existing.contains(view)) {
        layout = layout.panes.length > 1
            ? layout.closePane(pane.id)
            : ShellLayout._(
                _replace(layout.root, pane.id, (_) => pane.withView(null)),
                layout.focusedPaneId,
              );
      }
    }
    return layout;
  }

  /// Sets the ratio of the split at [path] (0 = first child, 1 = second,
  /// from the root).
  ShellLayout resize(List<int> path, double ratio) {
    ShellNode walk(ShellNode node, int depth) {
      if (node is! ShellSplit) return node;
      if (depth == path.length) {
        return node.copyWith(ratio: ShellSplit.clampRatio(ratio));
      }
      return path[depth] == 0
          ? node.copyWith(first: walk(node.first, depth + 1))
          : node.copyWith(second: walk(node.second, depth + 1));
    }

    return ShellLayout._(walk(root, 0), focusedPaneId);
  }

  /// Each pane's rectangle in a unit square.
  Map<String, Rect> paneRects() {
    final rects = <String, Rect>{};
    void walk(ShellNode node, Rect rect) {
      switch (node) {
        case ShellPane(:final id):
          rects[id] = rect;
        case ShellSplit(:final axis, :final ratio, :final first, :final second):
          if (axis == ShellSplitAxis.horizontal) {
            final x = rect.left + rect.width * ratio;
            walk(first, Rect.fromLTRB(rect.left, rect.top, x, rect.bottom));
            walk(second, Rect.fromLTRB(x, rect.top, rect.right, rect.bottom));
          } else {
            final y = rect.top + rect.height * ratio;
            walk(first, Rect.fromLTRB(rect.left, rect.top, rect.right, y));
            walk(second, Rect.fromLTRB(rect.left, y, rect.right, rect.bottom));
          }
      }
    }

    walk(root, const Rect.fromLTWH(0, 0, 1, 1));
    return rects;
  }

  /// The pane next to the focused one in [direction], or null: the
  /// closest pane that lies that way and overlaps it across.
  String? neighbor(ShellDirection direction) {
    final rects = paneRects();
    final from = rects[focusedPane.id]!;
    const epsilon = 1e-6;
    String? best;
    var bestDistance = double.infinity;
    for (final MapEntry(key: id, value: rect) in rects.entries) {
      if (id == focusedPane.id) continue;
      final double distance;
      final bool overlaps;
      switch (direction) {
        case ShellDirection.left:
          distance = from.left - rect.right;
          overlaps =
              rect.top < from.bottom - epsilon &&
              rect.bottom > from.top + epsilon;
        case ShellDirection.right:
          distance = rect.left - from.right;
          overlaps =
              rect.top < from.bottom - epsilon &&
              rect.bottom > from.top + epsilon;
        case ShellDirection.up:
          distance = from.top - rect.bottom;
          overlaps =
              rect.left < from.right - epsilon &&
              rect.right > from.left + epsilon;
        case ShellDirection.down:
          distance = rect.top - from.bottom;
          overlaps =
              rect.left < from.right - epsilon &&
              rect.right > from.left + epsilon;
      }
      if (!overlaps || distance < -epsilon) continue;
      // Ties (several panes along the edge): the one nearest the centre.
      final across = switch (direction) {
        ShellDirection.left ||
        ShellDirection.right => (rect.center.dy - from.center.dy).abs(),
        _ => (rect.center.dx - from.center.dx).abs(),
      };
      final score = distance * 10 + across;
      if (score < bestDistance) {
        bestDistance = score;
        best = id;
      }
    }
    return best;
  }

  String _nextPaneId() {
    var max = 0;
    for (final pane in panes) {
      final number = int.tryParse(pane.id.substring(1)) ?? 0;
      if (number > max) max = number;
    }
    return 'p${max + 1}';
  }

  static ShellNode _replace(
    ShellNode node,
    String paneId,
    ShellNode Function(ShellNode pane) replace,
  ) {
    switch (node) {
      case ShellPane(:final id):
        return id == paneId ? replace(node) : node;
      case ShellSplit(:final first, :final second):
        final a = _replace(first, paneId, replace);
        final b = _replace(second, paneId, replace);
        if (identical(a, first) && identical(b, second)) return node;
        return node.copyWith(first: a, second: b);
    }
  }

  Map<String, Object?> toJson() => {
    'root': root.toJson(),
    'focused': focusedPaneId,
  };

  /// A saved layout, or a single empty pane when [json] does not hold a
  /// usable one (more than [maxPanes] panes, repeated ids or views).
  static ShellLayout fromJson(Object? json) {
    if (json is! Map) return ShellLayout.single();
    final root = ShellNode.fromJson(json['root']);
    if (root == null) return ShellLayout.single();
    final layout = ShellLayout._(root, '');
    final panes = layout.panes;
    final ids = {for (final pane in panes) pane.id};
    final views = [
      for (final pane in panes)
        if (pane.view != null) pane.view,
    ];
    if (panes.length > maxPanes ||
        ids.length != panes.length ||
        views.toSet().length != views.length ||
        ids.any((id) => !RegExp(r'^p\d+$').hasMatch(id))) {
      return ShellLayout.single();
    }
    final focused = json['focused'];
    return ShellLayout._(
      root,
      focused is String && ids.contains(focused) ? focused : panes.first.id,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShellLayout &&
      other.root == root &&
      other.focusedPaneId == focusedPaneId;

  @override
  int get hashCode => Object.hash(root, focusedPaneId);

  @override
  String toString() => 'ShellLayout($root, focused: $focusedPaneId)';
}

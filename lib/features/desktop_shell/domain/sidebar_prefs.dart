import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:flutter/foundation.dart';

/// A user-made section of the sidebar ("Clients", "Infra") holding
/// machines in the user's order.
@immutable
class SidebarGroup {
  const SidebarGroup({
    required this.id,
    required this.name,
    this.machineIds = const [],
  });

  final String id;
  final String name;
  final List<String> machineIds;

  SidebarGroup copyWith({String? name, List<String>? machineIds}) =>
      SidebarGroup(
        id: id,
        name: name ?? this.name,
        machineIds: machineIds ?? this.machineIds,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'machines': machineIds,
  };

  static SidebarGroup? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    return SidebarGroup(
      id: id,
      name: name,
      machineIds: _strings(json['machines']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SidebarGroup &&
      other.id == id &&
      other.name == name &&
      listEquals(other.machineIds, machineIds);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(machineIds));
}

/// How the user arranged the sidebar, on this device: machine order,
/// the order of each machine's workspaces, pinned rows, groups and which
/// rows are expanded. Node keys are the sidebar's (see `sidebar_tree.dart`);
/// entries for things that no longer exist are harmless and ignored.
@immutable
class SidebarPrefs {
  const SidebarPrefs({
    this.machineOrder = const [],
    this.childOrder = const {},
    this.pinned = const [],
    this.groups = const [],
    this.expanded = const {},
  });

  /// Machine ids in the user's order; machines not listed follow in the
  /// machine list's order.
  final List<String> machineOrder;

  /// Per machine id: its workspaces' and sessions' node keys in order.
  final Map<String, List<String>> childOrder;

  /// Pinned node keys, in the order they show under "Pinned".
  final List<String> pinned;

  final List<SidebarGroup> groups;

  /// Rows opened or closed by the user; rows not listed use their default
  /// (machines and groups open, everything below closed).
  final Map<String, bool> expanded;

  bool isPinned(String key) => pinned.contains(key);

  /// The group [machineId] belongs to, if any.
  SidebarGroup? groupOf(String machineId) =>
      groups.where((group) => group.machineIds.contains(machineId)).firstOrNull;

  bool isExpanded(String key, {required bool byDefault}) =>
      expanded[key] ?? byDefault;

  SidebarPrefs copyWith({
    List<String>? machineOrder,
    Map<String, List<String>>? childOrder,
    List<String>? pinned,
    List<SidebarGroup>? groups,
    Map<String, bool>? expanded,
  }) => SidebarPrefs(
    machineOrder: machineOrder ?? this.machineOrder,
    childOrder: childOrder ?? this.childOrder,
    pinned: pinned ?? this.pinned,
    groups: groups ?? this.groups,
    expanded: expanded ?? this.expanded,
  );

  SidebarPrefs setExpanded(String key, bool value) =>
      copyWith(expanded: {...expanded, key: value});

  SidebarPrefs togglePin(String key) => copyWith(
    pinned: isPinned(key)
        ? [
            for (final other in pinned)
              if (other != key) other,
          ]
        : [...pinned, key],
  );

  /// Moves pinned [key] before [beforeKey] (or to the end).
  SidebarPrefs movePin(String key, String? beforeKey) {
    if (!isPinned(key) || key == beforeKey) return this;
    return copyWith(pinned: _moveBefore(pinned, key, beforeKey));
  }

  /// Moves machine [id] before [beforeId] (null: to the end), within
  /// [visibleOrder] (the machines as the sidebar shows them now). With
  /// [groupId] the machine joins that group (null: leaves any group).
  SidebarPrefs moveMachine(
    String id, {
    required List<String> visibleOrder,
    String? beforeId,
    String? groupId,
  }) {
    final order = _moveBefore(
      [
        ...visibleOrder,
        for (final known in machineOrder)
          if (!visibleOrder.contains(known)) known,
      ],
      id,
      beforeId,
    );
    final nextGroups = [
      for (final group in groups)
        if (group.id == groupId)
          group.copyWith(
            machineIds: _moveBefore(
              [
                for (final member in group.machineIds)
                  if (member != id) member,
              ],
              id,
              beforeId != null && group.machineIds.contains(beforeId)
                  ? beforeId
                  : null,
              insert: true,
            ),
          )
        else
          group.copyWith(
            machineIds: [
              for (final member in group.machineIds)
                if (member != id) member,
            ],
          ),
    ];
    return copyWith(machineOrder: order, groups: nextGroups);
  }

  /// Moves [key] (one of machine [machineId]'s workspace or session rows)
  /// before [beforeKey] (null: to the end), within [visibleOrder].
  SidebarPrefs moveChild(
    String machineId,
    String key, {
    required List<String> visibleOrder,
    String? beforeKey,
  }) {
    final known = childOrder[machineId] ?? const [];
    final order = _moveBefore(
      [
        ...visibleOrder,
        for (final other in known)
          if (!visibleOrder.contains(other)) other,
      ],
      key,
      beforeKey,
    );
    return copyWith(childOrder: {...childOrder, machineId: order});
  }

  SidebarPrefs addGroup(SidebarGroup group) =>
      copyWith(groups: [...groups, group]);

  SidebarPrefs renameGroup(String id, String name) => copyWith(
    groups: [
      for (final group in groups)
        group.id == id ? group.copyWith(name: name) : group,
    ],
  );

  /// Deletes group [id]; its machines go back to "Machines".
  SidebarPrefs removeGroup(String id) => copyWith(
    groups: [
      for (final group in groups)
        if (group.id != id) group,
    ],
  );

  /// Moves group [id] before [beforeId] (null: to the end).
  SidebarPrefs moveGroup(String id, String? beforeId) {
    final ids = [for (final group in groups) group.id];
    final order = _moveBefore(ids, id, beforeId);
    return copyWith(
      groups: [
        for (final groupId in order)
          groups.firstWhere((group) => group.id == groupId),
      ],
    );
  }

  /// Puts machine [machineId] in group [groupId] (null: no group).
  SidebarPrefs setGroup(String machineId, String? groupId) => copyWith(
    groups: [
      for (final group in groups)
        if (group.id == groupId)
          group.machineIds.contains(machineId)
              ? group
              : group.copyWith(machineIds: [...group.machineIds, machineId])
        else
          group.copyWith(
            machineIds: [
              for (final member in group.machineIds)
                if (member != machineId) member,
            ],
          ),
    ],
  );

  /// [items] in the saved [order] (by [keyOf]); items the order does not
  /// name keep their relative order after the named ones.
  static List<T> applyOrder<T>(
    List<T> items,
    String Function(T item) keyOf,
    List<String> order,
  ) {
    if (order.isEmpty) return items;
    final rank = {for (final (index, key) in order.indexed) key: index};
    final ranked =
        [
          for (final (index, item) in items.indexed)
            (rank[keyOf(item)] ?? order.length + index, index, item),
        ]..sort((a, b) {
          final byRank = a.$1.compareTo(b.$1);
          return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
        });
    return [for (final entry in ranked) entry.$3];
  }

  static List<String> _moveBefore(
    List<String> list,
    String key,
    String? beforeKey, {
    bool insert = false,
  }) {
    if (!insert && !list.contains(key)) return list;
    final result = [
      for (final other in list)
        if (other != key) other,
    ];
    final index = beforeKey == null ? -1 : result.indexOf(beforeKey);
    if (index < 0) {
      result.add(key);
    } else {
      result.insert(index, key);
    }
    return result;
  }

  /// These prefs with machine [from]'s order, rows, pins, group and open
  /// rows applied to machine [to] where [to] has none of its own: a saved
  /// machine that is this device shows as "This computer" in the sidebar,
  /// with what the user arranged for it.
  SidebarPrefs withMachineAlias(String from, String to) {
    if (from == to) return this;
    final fromPrefix = SidebarKeys.machine(from);
    final toPrefix = SidebarKeys.machine(to);
    final fromSession = '/s/${Uri.encodeComponent(from)}';
    final toSession = '/s/${Uri.encodeComponent(to)}';
    String alias(String key) {
      if (!SidebarKeys.isUnder(key, fromPrefix)) return key;
      var rest = key.substring(fromPrefix.length);
      if (rest.startsWith(fromSession)) {
        rest = '$toSession${rest.substring(fromSession.length)}';
      }
      return '$toPrefix$rest';
    }

    final toGrouped = groups.any((group) => group.machineIds.contains(to));
    return copyWith(
      machineOrder: machineOrder.contains(to)
          ? [
              for (final id in machineOrder)
                if (id != from) id,
            ]
          : [for (final id in machineOrder) id == from ? to : id],
      childOrder: {
        ...childOrder,
        if (!childOrder.containsKey(to) && childOrder[from] != null)
          to: [for (final key in childOrder[from]!) alias(key)],
      },
      pinned: {for (final key in pinned) alias(key)}.toList(),
      groups: [
        for (final group in groups)
          group.copyWith(
            machineIds: [
              for (final id in group.machineIds)
                if (id != from) id else if (!toGrouped) to,
            ],
          ),
      ],
      expanded: {
        for (final MapEntry(:key, :value) in expanded.entries)
          alias(key): value,
        ...{
          for (final MapEntry(:key, :value) in expanded.entries)
            if (!SidebarKeys.isUnder(key, fromPrefix)) key: value,
        },
      },
    );
  }

  Map<String, Object?> toJson() => {
    'machineOrder': machineOrder,
    'childOrder': childOrder,
    'pinned': pinned,
    'groups': [for (final group in groups) group.toJson()],
    'expanded': expanded,
  };

  static SidebarPrefs fromJson(Object? json) {
    if (json is! Map) return const SidebarPrefs();
    final childOrder = <String, List<String>>{};
    final rawChildren = json['childOrder'];
    if (rawChildren is Map) {
      for (final MapEntry(:key, :value) in rawChildren.entries) {
        if (key is String) childOrder[key] = _strings(value);
      }
    }
    final expanded = <String, bool>{};
    final rawExpanded = json['expanded'];
    if (rawExpanded is Map) {
      for (final MapEntry(:key, :value) in rawExpanded.entries) {
        if (key is String && value is bool) expanded[key] = value;
      }
    }
    final rawGroups = json['groups'];
    return SidebarPrefs(
      machineOrder: _strings(json['machineOrder']),
      childOrder: childOrder,
      pinned: _strings(json['pinned']),
      groups: [
        if (rawGroups is List)
          for (final raw in rawGroups) ?SidebarGroup.fromJson(raw),
      ],
      expanded: expanded,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SidebarPrefs &&
      listEquals(other.machineOrder, machineOrder) &&
      mapEquals(
        other.childOrder.map((key, value) => MapEntry(key, value.join('\n'))),
        childOrder.map((key, value) => MapEntry(key, value.join('\n'))),
      ) &&
      listEquals(other.pinned, pinned) &&
      listEquals(other.groups, groups) &&
      mapEquals(other.expanded, expanded);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(machineOrder),
    Object.hashAll(pinned),
    Object.hashAll(groups),
    expanded.length,
    childOrder.length,
  );
}

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (item is String) item,
];

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A device as the hub's meta file lists it.
@immutable
class SyncDeviceInfo {
  const SyncDeviceInfo({
    required this.id,
    required this.name,
    this.platform = '',
    this.lastSeen,
    this.publicKey,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime? lastSeen;

  /// `ssh-ed25519 AAAA…` when the device reaches the hub with a key added
  /// by "Add a device" (so removing it can revoke that key).
  final String? publicKey;

  SyncDeviceInfo copyWith({DateTime? lastSeen, String? publicKey}) =>
      SyncDeviceInfo(
        id: id,
        name: name,
        platform: platform,
        lastSeen: lastSeen ?? this.lastSeen,
        publicKey: publicKey ?? this.publicKey,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (platform.isNotEmpty) 'platform': platform,
    if (lastSeen != null) 'lastSeen': lastSeen!.toUtc().toIso8601String(),
    if (publicKey != null) 'publicKey': publicKey,
  };

  static SyncDeviceInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty) return null;
    final platform = json['platform'];
    final publicKey = json['publicKey'];
    return SyncDeviceInfo(
      id: id,
      name: name is String && name.isNotEmpty ? name : 'Device',
      platform: platform is String ? platform : '',
      lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? ''),
      publicKey: publicKey is String && publicKey.isNotEmpty ? publicKey : null,
    );
  }
}

/// The small unencrypted `<vault>.meta` next to the bundle: enough to
/// tell whether anything changed without downloading the bundle, and the
/// device list. It holds no settings or secrets.
@immutable
class SyncHubMeta {
  const SyncHubMeta({
    required this.version,
    this.updatedAt,
    this.updatedBy = '',
    this.devices = const [],
    this.revoked = const [],
  });

  static const format = 'conductore.sync-meta';

  /// Bumped on every push; the hub's compare-and-swap checks it.
  final int version;
  final DateTime? updatedAt;
  final String updatedBy;
  final List<SyncDeviceInfo> devices;

  /// Ids of removed devices, so a stale copy cannot list them again.
  final List<String> revoked;

  /// Compact JSON with `version` first: the hub's shell script reads it
  /// with a plain pattern match.
  String encode() => jsonEncode({
    'version': version,
    'format': format,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    'updatedBy': updatedBy,
    'devices': [for (final device in devices) device.toJson()],
    if (revoked.isNotEmpty) 'revoked': revoked,
  });

  static SyncHubMeta? decode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['format'] != format) return null;
      final version = json['version'];
      final updatedBy = json['updatedBy'];
      return SyncHubMeta(
        version: version is int ? version : 0,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        updatedBy: updatedBy is String ? updatedBy : '',
        devices: [
          for (final raw in (json['devices'] as List?) ?? const [])
            ?SyncDeviceInfo.fromJson(raw),
        ],
        revoked: [
          for (final id in (json['revoked'] as List?) ?? const [])
            if (id is String) id,
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// A `conductore-device` line of the hub's `~/.ssh/authorized_keys`.
@immutable
class AuthorizedDeviceKey {
  const AuthorizedDeviceKey({required this.publicKey, required this.name});

  /// `ssh-ed25519 AAAA…`
  final String publicKey;
  final String name;
}

enum SyncPushOutcome {
  ok,

  /// Another device pushed since this one pulled: pull, merge, retry.
  conflict,

  /// The hub is locked by another push that is still running.
  busy,
}

/// The sync hub: files under `~/.conductore/sync/` on one saved machine,
/// reached over the app's SSH/SFTP stack. Nothing runs on the host.
abstract interface class SyncHub {
  Future<SyncHubMeta?> readMeta(String vaultId);

  /// Vault ids with a meta file on the hub.
  Future<List<String>> listVaults();

  Future<Uint8List> readBundle(String vaultId);

  /// Replaces the bundle and meta if the hub's meta version is still
  /// [expectedVersion] (0 when there was none).
  Future<SyncPushOutcome> push(
    String vaultId, {
    required Uint8List bundle,
    required SyncHubMeta meta,
    required int expectedVersion,
  });

  Future<void> deleteVault(String vaultId);

  Future<List<AuthorizedDeviceKey>> deviceKeys();

  /// Adds `<publicKey> conductore-device <name>` unless the key is there.
  Future<void> addDeviceKey(String publicKey, String name);

  /// Removes every line with [publicKey]'s key material.
  Future<void> removeDeviceKey(String publicKey);

  Future<void> close();
}

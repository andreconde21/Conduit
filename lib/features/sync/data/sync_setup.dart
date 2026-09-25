import 'dart:convert';

import 'package:conduit/features/sync/data/sync_crypto.dart';
import 'package:conduit/features/sync/domain/sync_setup_code.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;

/// An ed25519 SSH key for one device, rebuilt from its 32-byte seed (the
/// setup code carries the seed, not a PEM, to keep the QR code small).
@immutable
class DeviceSshKey {
  const DeviceSshKey._(this.seed, this._pair);

  factory DeviceSshKey.fromSeed(Uint8List seed, {String comment = ''}) {
    final signing = ed25519.SigningKey.fromSeed(seed);
    return DeviceSshKey._(
      Uint8List.fromList(seed),
      OpenSSHEd25519KeyPair(
        Uint8List.fromList(signing.verifyKey.asTypedList),
        Uint8List.fromList(signing.asTypedList),
        comment,
      ),
    );
  }

  factory DeviceSshKey.generate({String comment = ''}) =>
      DeviceSshKey.fromSeed(SyncCrypto.randomBytes(32), comment: comment);

  final Uint8List seed;
  final OpenSSHEd25519KeyPair _pair;

  /// Unencrypted OpenSSH private key, as a saved machine stores it.
  String get privateKeyPem => _pair.toPem();

  /// `ssh-ed25519 AAAA…`
  String get publicKey =>
      'ssh-ed25519 ${base64Encode(_pair.toPublicKey().encode())}';
}

/// The secret half of a setup code.
@immutable
class SyncSetupSecret {
  const SyncSetupSecret({
    required this.deviceId,
    required this.deviceName,
    required this.deviceKeySeed,
    required this.syncKey,
  });

  final String deviceId;
  final String deviceName;
  final Uint8List deviceKeySeed;
  final SyncKey syncKey;

  Map<String, Object?> toJson() => {
    'd': deviceId,
    'n': deviceName,
    'k': base64Encode(deviceKeySeed),
    's': syncKey.toJson(),
  };

  static SyncSetupSecret? fromJson(Object? json) {
    if (json is! Map) return null;
    final deviceId = json['d'];
    final deviceName = json['n'];
    final key = SyncKey.fromJson(json['s']);
    if (deviceId is! String || deviceName is! String || key == null) {
      return null;
    }
    try {
      final seed = base64Decode(json['k'] as String);
      if (seed.length != 32) return null;
      return SyncSetupSecret(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceKeySeed: seed,
        syncKey: key,
      );
    } catch (_) {
      return null;
    }
  }
}

class SyncSetupException implements Exception {
  const SyncSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Seals and opens setup codes.
class SyncSetupCodec {
  const SyncSetupCodec({
    this.crypto = const SyncCrypto(),
    this.params = KdfParams.setupCode,
  });

  final SyncCrypto crypto;
  final KdfParams params;

  Future<SyncSetupOffer> seal({
    required String hubName,
    required String host,
    required int port,
    required String username,
    required String hostKeyType,
    required String hostKeyFingerprint,
    required String hubHostId,
    required String vaultId,
    required SyncSetupSecret secret,
    required List<String> words,
  }) async {
    final code = SetupWords.normalize(words.join(' '));
    if (code == null) throw ArgumentError.value(words, 'words');
    final salt = SyncCrypto.randomBytes(16);
    final unsealed = SyncSetupOffer(
      hubName: hubName,
      host: host,
      port: port,
      username: username,
      hostKeyType: hostKeyType,
      hostKeyFingerprint: hostKeyFingerprint,
      hubHostId: hubHostId,
      vaultId: vaultId,
      salt: salt,
      sealed: Uint8List(0),
      memoryKiB: params.memoryKiB,
      iterations: params.iterations,
    );
    final key = await crypto.deriveKey(code, salt, params);
    final sealed = await crypto.sealRaw(
      key.bytes,
      Uint8List.fromList(utf8.encode(jsonEncode(secret.toJson()))),
      unsealed.associatedData,
    );
    return SyncSetupOffer(
      hubName: hubName,
      host: host,
      port: port,
      username: username,
      hostKeyType: hostKeyType,
      hostKeyFingerprint: hostKeyFingerprint,
      hubHostId: hubHostId,
      vaultId: vaultId,
      salt: salt,
      sealed: sealed,
      memoryKiB: params.memoryKiB,
      iterations: params.iterations,
    );
  }

  /// Opens [offer] with the words as typed.
  Future<SyncSetupSecret> open(SyncSetupOffer offer, String words) async {
    final code = SetupWords.normalize(words);
    if (code == null) {
      throw const SyncSetupException(
        'Type the six words shown on the other device.',
      );
    }
    final KdfParams offerParams;
    try {
      offerParams = KdfParams.fromJson({
        'name': 'argon2id',
        'memoryKiB': offer.memoryKiB,
        'iterations': offer.iterations,
        'parallelism': 1,
      });
    } on SyncCryptoException {
      throw const SyncSetupException('This setup code is not supported.');
    }
    final key = await crypto.deriveKey(code, offer.salt, offerParams);
    final Uint8List clear;
    try {
      clear = await crypto.openRaw(
        key.bytes,
        offer.sealed,
        offer.associatedData,
      );
    } on SyncCryptoException {
      throw const SyncSetupException(
        'Those words do not match this setup code.',
      );
    }
    final secret = SyncSetupSecret.fromJson(jsonDecode(utf8.decode(clear)));
    if (secret == null) {
      throw const SyncSetupException('This setup code is damaged.');
    }
    return secret;
  }
}

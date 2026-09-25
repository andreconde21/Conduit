import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:conduit/features/sync/domain/canonical_json.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Argon2id cost. Stored next to every salt, so the cost can rise later
/// without breaking older bundles.
@immutable
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    this.parallelism = 1,
  });

  /// Passphrases (sync key, backups): 64 MiB, 3 passes. Under a second on
  /// a current phone, and the RFC 9106 memory-constrained profile.
  static const passphrase = KdfParams(memoryKiB: 65536, iterations: 3);

  /// The six-word setup code: 19 MiB, 2 passes (OWASP's minimum). The code
  /// is 48 random bits and lives for one pairing, so a lighter cost still
  /// puts brute force of a photographed QR out of reach.
  static const setupCode = KdfParams(memoryKiB: 19456, iterations: 2);

  /// Tests only: fast, never for real data.
  @visibleForTesting
  static const insecureFast = KdfParams(memoryKiB: 64, iterations: 1);

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, Object?> toJson() => {
    'name': 'argon2id',
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
  };

  static KdfParams fromJson(Object? json) {
    if (json is! Map || json['name'] != 'argon2id') {
      throw const SyncCryptoException.unsupported();
    }
    final memory = json['memoryKiB'];
    final iterations = json['iterations'];
    final parallelism = json['parallelism'];
    // Bounds keep a hostile file from asking for gigabytes or hours.
    if (memory is! int ||
        iterations is! int ||
        parallelism is! int ||
        memory < 8 ||
        memory > 1024 * 1024 ||
        iterations < 1 ||
        iterations > 64 ||
        parallelism < 1 ||
        parallelism > 16) {
      throw const SyncCryptoException.unsupported();
    }
    return KdfParams(
      memoryKiB: memory,
      iterations: iterations,
      parallelism: parallelism,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);
}

/// A 256-bit key and how it was derived, so a bundle sealed with it can
/// name its salt and cost and be opened again from the passphrase.
@immutable
class SyncKey {
  const SyncKey({
    required this.bytes,
    required this.salt,
    required this.params,
  });

  final Uint8List bytes;
  final Uint8List salt;
  final KdfParams params;

  bool derivedWith(Uint8List otherSalt, KdfParams otherParams) =>
      params == otherParams && listEquals(salt, otherSalt);

  Map<String, Object?> toJson() => {
    'key': base64Encode(bytes),
    'salt': base64Encode(salt),
    'kdf': params.toJson(),
  };

  static SyncKey? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final bytes = base64Decode(json['key'] as String);
      final salt = base64Decode(json['salt'] as String);
      if (bytes.length != 32 || salt.length < 16) return null;
      return SyncKey(
        bytes: bytes,
        salt: salt,
        params: KdfParams.fromJson(json['kdf']),
      );
    } catch (_) {
      return null;
    }
  }
}

enum SyncCryptoError { wrongKey, unsupported, damaged }

class SyncCryptoException implements Exception {
  const SyncCryptoException(this.error, this.message);

  const SyncCryptoException.wrongKey()
    : error = SyncCryptoError.wrongKey,
      message = 'The passphrase is wrong or the data was changed.';

  const SyncCryptoException.unsupported()
    : error = SyncCryptoError.unsupported,
      message = 'This encrypted data uses a format this app does not know.';

  const SyncCryptoException.damaged()
    : error = SyncCryptoError.damaged,
      message = 'This does not look like a Conductore bundle.';

  final SyncCryptoError error;
  final String message;

  @override
  String toString() => message;
}

/// The readable header of a bundle: format, vault and key derivation. It
/// is authenticated (the AEAD's associated data), not secret.
@immutable
class BundleHeader {
  const BundleHeader({
    required this.salt,
    required this.params,
    required this.nonce,
    this.vaultId,
  });

  final Uint8List salt;
  final KdfParams params;
  final Uint8List nonce;
  final String? vaultId;

  Map<String, Object?> toJson() => {
    'format': SyncCrypto.bundleFormat,
    'version': SyncCrypto.bundleVersion,
    if (vaultId != null) 'vault': vaultId,
    'kdf': {...params.toJson(), 'salt': base64Encode(salt)},
    'cipher': {'name': SyncCrypto.cipherName, 'nonce': base64Encode(nonce)},
  };
}

/// End-to-end encryption for sync bundles and backup files, which share
/// one format:
///
/// ```json
/// {"format":"conductore.bundle","version":2,"vault":"…",
///  "kdf":{"name":"argon2id","memoryKiB":65536,"iterations":3,
///         "parallelism":1,"salt":"…"},
///  "cipher":{"name":"xchacha20-poly1305","nonce":"…"},
///  "ciphertext":"…"}
/// ```
///
/// The key is Argon2id(passphrase, salt); the body is XChaCha20-Poly1305
/// with a random 192-bit nonce and the canonical header JSON as associated
/// data, so neither the header nor the body can be altered unnoticed.
/// Everything happens on the device; the hub only ever stores the result.
class SyncCrypto {
  const SyncCrypto({
    this.params = KdfParams.passphrase,
    this.useIsolate = true,
  });

  static const bundleFormat = 'conductore.bundle';
  static const bundleVersion = 2;
  static const cipherName = 'xchacha20-poly1305';
  static const _saltLength = 16;
  static const _nonceLength = 24;

  /// Cost for new keys.
  final KdfParams params;

  /// Runs Argon2id on a background isolate so the UI keeps drawing.
  final bool useIsolate;

  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// A new key for [passphrase] with a fresh salt.
  Future<SyncKey> newKey(String passphrase) {
    return deriveKey(passphrase, randomBytes(_saltLength), params);
  }

  Future<SyncKey> deriveKey(
    String passphrase,
    Uint8List salt,
    KdfParams params,
  ) async {
    final bytes = useIsolate
        ? await Isolate.run(() => _argon2id(passphrase, salt, params))
        : await _argon2id(passphrase, salt, params);
    return SyncKey(bytes: bytes, salt: salt, params: params);
  }

  static Future<Uint8List> _argon2id(
    String passphrase,
    Uint8List salt,
    KdfParams params,
  ) async {
    final algorithm = Argon2id(
      memory: params.memoryKiB,
      iterations: params.iterations,
      parallelism: params.parallelism,
      hashLength: 32,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Encrypts [plaintext] into a bundle file.
  Future<Uint8List> seal(
    SyncKey key,
    Uint8List plaintext, {
    String? vaultId,
  }) async {
    final header = BundleHeader(
      salt: key.salt,
      params: key.params,
      nonce: randomBytes(_nonceLength),
      vaultId: vaultId,
    );
    final headerJson = header.toJson();
    final box = await Xchacha20.poly1305Aead().encrypt(
      plaintext,
      secretKey: SecretKey(key.bytes),
      nonce: header.nonce,
      aad: utf8.encode(canonicalJson(headerJson)),
    );
    final document = {
      ...headerJson,
      'ciphertext': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
    return Uint8List.fromList(utf8.encode('${jsonEncode(document)}\n'));
  }

  /// Reads a bundle's header without decrypting it.
  static BundleHeader readHeader(Uint8List bundle) {
    final document = _decode(bundle);
    return _header(document);
  }

  /// Whether [bytes] look like a bundle (as opposed to an older backup).
  static bool isBundle(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map && decoded['format'] == bundleFormat;
    } catch (_) {
      return false;
    }
  }

  /// Decrypts [bundle] with [key] when it was derived with the bundle's
  /// salt and cost, else with a key derived from [passphrase].
  Future<Uint8List> open(
    Uint8List bundle, {
    SyncKey? key,
    String? passphrase,
  }) async {
    final document = _decode(bundle);
    final header = _header(document);
    var usable = key != null && key.derivedWith(header.salt, header.params)
        ? key
        : null;
    if (usable == null) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const SyncCryptoException.wrongKey();
      }
      usable = await deriveKey(passphrase, header.salt, header.params);
    }
    final Uint8List sealed;
    try {
      sealed = base64Decode(document['ciphertext'] as String);
    } catch (_) {
      throw const SyncCryptoException.damaged();
    }
    if (sealed.length < 16) throw const SyncCryptoException.damaged();
    final headerJson = Map<String, Object?>.of(document)..remove('ciphertext');
    try {
      final clear = await Xchacha20.poly1305Aead().decrypt(
        SecretBox(
          sealed.sublist(0, sealed.length - 16),
          nonce: header.nonce,
          mac: Mac(sealed.sublist(sealed.length - 16)),
        ),
        secretKey: SecretKey(usable.bytes),
        aad: utf8.encode(canonicalJson(headerJson)),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const SyncCryptoException.wrongKey();
    }
  }

  /// Seals a small secret under [key] (the setup code's payload), without
  /// the bundle's JSON framing: nonce ‖ ciphertext ‖ tag.
  Future<Uint8List> sealRaw(
    Uint8List key,
    Uint8List plaintext,
    List<int> aad,
  ) async {
    final nonce = randomBytes(_nonceLength);
    final box = await Xchacha20.poly1305Aead().encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> openRaw(
    Uint8List key,
    Uint8List sealed,
    List<int> aad,
  ) async {
    if (sealed.length < _nonceLength + 16) {
      throw const SyncCryptoException.damaged();
    }
    try {
      final clear = await Xchacha20.poly1305Aead().decrypt(
        SecretBox(
          sealed.sublist(_nonceLength, sealed.length - 16),
          nonce: sealed.sublist(0, _nonceLength),
          mac: Mac(sealed.sublist(sealed.length - 16)),
        ),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const SyncCryptoException.wrongKey();
    }
  }

  static Map<String, Object?> _decode(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      // Falls through to the error below.
    }
    throw const SyncCryptoException.damaged();
  }

  static BundleHeader _header(Map<String, Object?> document) {
    if (document['format'] != bundleFormat) {
      throw const SyncCryptoException.damaged();
    }
    final version = document['version'];
    if (version != bundleVersion) {
      throw const SyncCryptoException.unsupported();
    }
    final kdf = document['kdf'];
    final cipher = document['cipher'];
    if (kdf is! Map || cipher is! Map || cipher['name'] != cipherName) {
      throw const SyncCryptoException.unsupported();
    }
    final params = KdfParams.fromJson(kdf);
    try {
      final salt = base64Decode(kdf['salt'] as String);
      final nonce = base64Decode(cipher['nonce'] as String);
      if (salt.length < _saltLength || nonce.length != _nonceLength) {
        throw const SyncCryptoException.damaged();
      }
      final vault = document['vault'];
      return BundleHeader(
        salt: salt,
        params: params,
        nonce: nonce,
        vaultId: vault is String ? vault : null,
      );
    } on SyncCryptoException {
      rethrow;
    } catch (_) {
      throw const SyncCryptoException.damaged();
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/sync/data/sync_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const crypto = SyncCrypto(params: KdfParams.insecureFast, useIsolate: false);

  test('Argon2id matches the reference implementation', () async {
    // echo -n 'correct horse battery staple' |
    //   argon2 somesaltsomesalt -id -t 2 -k 1024 -p 1 -l 32 -r
    final key = await crypto.deriveKey(
      'correct horse battery staple',
      Uint8List.fromList(utf8.encode('somesaltsomesalt')),
      const KdfParams(memoryKiB: 1024, iterations: 2),
    );
    expect(
      key.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '265f5a311885766039daeaa28af0ea615a2de9f573ddeacd52558fa31ca0e3a0',
    );
  });

  test('the production cost runs on a background isolate', () async {
    const real = SyncCrypto();
    final key = await real.newKey('Correct-Horse-9');
    expect(key.bytes, hasLength(32));
    expect(key.params, KdfParams.passphrase);
  });

  test('round trip with the key and with the passphrase', () async {
    final key = await crypto.newKey('Correct-Horse-9');
    final plaintext = Uint8List.fromList(utf8.encode('{"hello":"world"}'));

    final bundle = await crypto.seal(key, plaintext, vaultId: 'v1');
    final text = utf8.decode(bundle);
    expect(text, isNot(contains('hello')));
    expect(text, contains('"format":"conductore.bundle"'));
    expect(text, contains('"name":"argon2id"'));
    expect(text, contains('"name":"xchacha20-poly1305"'));
    expect(SyncCrypto.readHeader(bundle).vaultId, 'v1');

    expect(await crypto.open(bundle, key: key), plaintext);
    expect(await crypto.open(bundle, passphrase: 'Correct-Horse-9'), plaintext);
  });

  test('every seal uses a new nonce', () async {
    final key = await crypto.newKey('Correct-Horse-9');
    final plaintext = Uint8List.fromList([1, 2, 3]);
    final a = await crypto.seal(key, plaintext);
    final b = await crypto.seal(key, plaintext);
    expect(
      SyncCrypto.readHeader(a).nonce,
      isNot(SyncCrypto.readHeader(b).nonce),
    );
  });

  test('a wrong passphrase is refused', () async {
    final key = await crypto.newKey('Correct-Horse-9');
    final bundle = await crypto.seal(key, Uint8List.fromList([1, 2, 3]));
    await expectLater(
      crypto.open(bundle, passphrase: 'Wrong-Horse-9'),
      throwsA(
        isA<SyncCryptoException>().having(
          (e) => e.error,
          'error',
          SyncCryptoError.wrongKey,
        ),
      ),
    );
    await expectLater(crypto.open(bundle), throwsA(isA<SyncCryptoException>()));
  });

  test('a changed header or body is refused', () async {
    final key = await crypto.newKey('Correct-Horse-9');
    final bundle = await crypto.seal(
      key,
      Uint8List.fromList([1, 2, 3]),
      vaultId: 'v1',
    );
    final document = jsonDecode(utf8.decode(bundle)) as Map<String, Object?>;

    final renamed = {...document, 'vault': 'v2'};
    await expectLater(
      crypto.open(_bytes(renamed), key: key),
      throwsA(isA<SyncCryptoException>()),
    );

    final sealed = base64Decode(document['ciphertext']! as String);
    sealed[0] ^= 1;
    final flipped = {...document, 'ciphertext': base64Encode(sealed)};
    await expectLater(
      crypto.open(_bytes(flipped), key: key),
      throwsA(
        isA<SyncCryptoException>().having(
          (e) => e.error,
          'error',
          SyncCryptoError.wrongKey,
        ),
      ),
    );
  });

  test('unknown versions and ciphers are reported as unsupported', () async {
    final key = await crypto.newKey('Correct-Horse-9');
    final bundle = await crypto.seal(key, Uint8List.fromList([1]));
    final document = jsonDecode(utf8.decode(bundle)) as Map<String, Object?>;
    for (final changed in [
      {...document, 'version': 3},
      {
        ...document,
        'cipher': {'name': 'rot13', 'nonce': ''},
      },
      {
        ...document,
        'kdf': {'name': 'argon2id', 'memoryKiB': 1 << 30, 'iterations': 3},
      },
    ]) {
      await expectLater(
        crypto.open(_bytes(changed), key: key),
        throwsA(
          isA<SyncCryptoException>().having(
            (e) => e.error,
            'error',
            SyncCryptoError.unsupported,
          ),
        ),
      );
    }
    await expectLater(
      crypto.open(Uint8List.fromList(utf8.encode('not json'))),
      throwsA(
        isA<SyncCryptoException>().having(
          (e) => e.error,
          'error',
          SyncCryptoError.damaged,
        ),
      ),
    );
  });

  test('raw seal round trip and wrong key', () async {
    final key = SyncCrypto.randomBytes(32);
    final sealed = await crypto.sealRaw(key, Uint8List.fromList([9, 8]), [1]);
    expect(await crypto.openRaw(key, sealed, [1]), [9, 8]);
    await expectLater(
      crypto.openRaw(key, sealed, [2]),
      throwsA(isA<SyncCryptoException>()),
    );
    await expectLater(
      crypto.openRaw(SyncCrypto.randomBytes(32), sealed, [1]),
      throwsA(isA<SyncCryptoException>()),
    );
  });

  test('a stored key survives JSON', () async {
    final key = await crypto.newKey('Correct-Horse-9');
    final restored = SyncKey.fromJson(jsonDecode(jsonEncode(key.toJson())));
    expect(restored!.bytes, key.bytes);
    expect(restored.derivedWith(key.salt, key.params), isTrue);
  });
}

Uint8List _bytes(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

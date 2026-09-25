import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:conduit/features/sync/data/sync_crypto.dart';
import 'package:conduit/features/sync/data/sync_setup.dart';
import 'package:conduit/features/sync/domain/sync_hub_commands.dart';
import 'package:conduit/features/sync/domain/sync_setup_code.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

const _crypto = SyncCrypto(params: KdfParams.insecureFast, useIsolate: false);
const _codec = SyncSetupCodec(crypto: _crypto, params: KdfParams.insecureFast);

void main() {
  group('SetupWords', () {
    test('256 distinct words, no two sharing four letters', () {
      expect(SetupWords.list, hasLength(256));
      expect(SetupWords.list.toSet(), hasLength(256));
      expect(
        SetupWords.list.map((w) => w.substring(0, min(4, w.length))).toSet(),
        hasLength(256),
      );
      expect(
        SetupWords.list.every((w) => RegExp(r'^[a-z]{3,6}$').hasMatch(w)),
        isTrue,
      );
    });

    test('generates six known words', () {
      final words = SetupWords.generate(Random(1));
      expect(words, hasLength(6));
      expect(SetupWords.normalize(words.join(' ')), words.join(' '));
    });

    test('normalizes case and separators, rejects anything else', () {
      expect(
        SetupWords.normalize(' Acid-ACORN, actor\nadapt agent  alarm '),
        'acid acorn actor adapt agent alarm',
      );
      expect(SetupWords.normalize('acid acorn actor adapt agent'), isNull);
      expect(SetupWords.normalize('acid acorn actor adapt agent zzz'), isNull);
    });
  });

  group('device SSH key', () {
    test('rebuilds from its seed into a key the SSH stack loads', () {
      final key = DeviceSshKey.generate();
      final again = DeviceSshKey.fromSeed(key.seed);
      expect(again.publicKey, key.publicKey);
      expect(key.publicKey, startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
      // Accepted by the authorized_keys commands.
      expect(SyncHubCommands.splitPublicKey(key.publicKey).$1, 'ssh-ed25519');

      final parsed = SSHKeyPair.fromPem(key.privateKeyPem).single;
      expect(
        'ssh-ed25519 ${base64Encode(parsed.toPublicKey().encode())}',
        key.publicKey,
      );
    });
  });

  group('setup code', () {
    Future<(SyncSetupOffer, List<String>, SyncSetupSecret)> sealed() async {
      final words = SetupWords.generate();
      final secret = SyncSetupSecret(
        deviceId: 'a' * 32,
        deviceName: 'iPad',
        deviceKeySeed: DeviceSshKey.generate().seed,
        syncKey: await _crypto.newKey('Correct-Horse-9'),
      );
      final offer = await _codec.seal(
        hubName: 'Workstation',
        host: 'ws.tail.ts.net',
        port: 22,
        username: 'andre',
        hostKeyType: 'ssh-ed25519',
        hostKeyFingerprint: 'SHA256:abc',
        hubHostId: 'hub-id',
        vaultId: 'b' * 32,
        secret: secret,
        words: words,
      );
      return (offer, words, secret);
    }

    test('encodes to a compact QR string and back', () async {
      final (offer, _, _) = await sealed();
      final text = offer.encode();
      expect(text, startsWith('conductore-sync:1:'));
      expect(text.length, lessThan(900));
      // A pasted code may arrive wrapped.
      final wrapped = text.replaceAllMapped(
        RegExp('.{40}'),
        (m) => '${m[0]}\n',
      );
      final back = SyncSetupOffer.decode(wrapped)!;
      expect(back.host, 'ws.tail.ts.net');
      expect(back.hostKeyFingerprint, 'SHA256:abc');
      expect(back.sealed, offer.sealed);
      expect(SyncSetupOffer.decode('https://example.com'), isNull);
      expect(SyncSetupOffer.decode('conductore-sync:1:!!!'), isNull);
    });

    test('opens with the words and carries the secrets', () async {
      final (offer, words, secret) = await sealed();
      final opened = await _codec.open(
        SyncSetupOffer.decode(offer.encode())!,
        words.join(' ').toUpperCase(),
      );
      expect(opened.deviceId, secret.deviceId);
      expect(opened.deviceKeySeed, secret.deviceKeySeed);
      expect(opened.syncKey.bytes, secret.syncKey.bytes);
    });

    test('the QR alone is not enough: wrong words fail', () async {
      final (offer, words, _) = await sealed();
      final wrong = [...words]..[0] = words[0] == 'acid' ? 'acorn' : 'acid';
      await expectLater(
        _codec.open(offer, wrong.join(' ')),
        throwsA(isA<SyncSetupException>()),
      );
      await expectLater(
        _codec.open(offer, 'not six words'),
        throwsA(isA<SyncSetupException>()),
      );
    });

    test('a swapped host or host key breaks the seal', () async {
      final (offer, words, _) = await sealed();
      final json =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    offer.encode().substring(SyncSetupOffer.prefix.length),
                  ),
                ),
              )
              as Map<String, Object?>;
      for (final change in [
        {'h': 'evil.example.com'},
        {'fp': 'SHA256:evil'},
      ]) {
        final forged = SyncSetupOffer.decode(
          '${SyncSetupOffer.prefix}'
          '${base64UrlEncode(utf8.encode(jsonEncode({...json, ...change})))}',
        )!;
        await expectLater(
          _codec.open(forged, words.join(' ')),
          throwsA(isA<SyncSetupException>()),
        );
      }
    });
  });

  test('secret JSON rejects a short seed', () {
    expect(
      SyncSetupSecret.fromJson({
        'd': 'x',
        'n': 'y',
        'k': base64Encode(Uint8List(8)),
        's': {'key': '', 'salt': ''},
      }),
      isNull,
    );
  });
}

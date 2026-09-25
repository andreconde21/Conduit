import 'dart:convert';
import 'dart:math';

import 'package:conduit/features/sync/domain/canonical_json.dart';
import 'package:flutter/foundation.dart';

/// The six words that unlock a setup code. 256 short, distinct words (no
/// two share their first four letters), so six of them carry 48 random
/// bits; the setup code's Argon2id cost makes guessing them from a
/// photographed QR code impractical.
abstract final class SetupWords {
  static const count = 6;

  static const list = [
    'acid',
    'acorn',
    'actor',
    'adapt',
    'agent',
    'alarm',
    'album',
    'alert',
    'alpha',
    'amber',
    'angle',
    'ankle',
    'apple',
    'april',
    'arena',
    'arrow',
    'aspen',
    'atlas',
    'attic',
    'audio',
    'autumn',
    'badge',
    'bagel',
    'baker',
    'balmy',
    'bamboo',
    'banjo',
    'barley',
    'basil',
    'beach',
    'beard',
    'beetle',
    'bench',
    'berry',
    'bingo',
    'birch',
    'bison',
    'blade',
    'blank',
    'blaze',
    'bloom',
    'blue',
    'board',
    'bonus',
    'boost',
    'bottle',
    'brave',
    'bread',
    'brick',
    'bridge',
    'brook',
    'brush',
    'bubble',
    'bucket',
    'buddy',
    'cabin',
    'cable',
    'cactus',
    'camel',
    'candle',
    'canoe',
    'canvas',
    'canyon',
    'cargo',
    'carpet',
    'carrot',
    'castle',
    'cedar',
    'chair',
    'chalk',
    'cherry',
    'chess',
    'chief',
    'chili',
    'cider',
    'cinema',
    'circle',
    'citrus',
    'clay',
    'cliff',
    'clock',
    'cloud',
    'clover',
    'coast',
    'cobalt',
    'cocoa',
    'comet',
    'coral',
    'cotton',
    'cousin',
    'crane',
    'crayon',
    'crown',
    'cube',
    'curry',
    'daisy',
    'dance',
    'delta',
    'denim',
    'desert',
    'diary',
    'dingo',
    'donut',
    'dragon',
    'dream',
    'drum',
    'eagle',
    'earth',
    'easel',
    'echo',
    'elbow',
    'ember',
    'engine',
    'envoy',
    'equal',
    'fabric',
    'falcon',
    'fence',
    'ferry',
    'fiber',
    'field',
    'fig',
    'flame',
    'flute',
    'focus',
    'forest',
    'fossil',
    'fox',
    'frost',
    'fruit',
    'galaxy',
    'garden',
    'garlic',
    'gecko',
    'ginger',
    'globe',
    'glove',
    'grape',
    'gravel',
    'guitar',
    'hammer',
    'harbor',
    'hazel',
    'helmet',
    'hero',
    'honey',
    'hotel',
    'husky',
    'igloo',
    'indigo',
    'island',
    'ivory',
    'jacket',
    'jaguar',
    'jelly',
    'jewel',
    'jigsaw',
    'jungle',
    'kayak',
    'kettle',
    'kiwi',
    'koala',
    'ladder',
    'lagoon',
    'lake',
    'lemon',
    'lily',
    'linen',
    'lion',
    'lizard',
    'lotus',
    'lunar',
    'magnet',
    'mango',
    'maple',
    'marble',
    'meadow',
    'melon',
    'meteor',
    'mint',
    'mirror',
    'mocha',
    'monkey',
    'moose',
    'mosaic',
    'motor',
    'muffin',
    'nectar',
    'needle',
    'nickel',
    'noodle',
    'north',
    'oasis',
    'ocean',
    'olive',
    'onion',
    'opal',
    'orbit',
    'otter',
    'oxygen',
    'paddle',
    'palace',
    'panda',
    'paper',
    'parrot',
    'peach',
    'pebble',
    'pencil',
    'pepper',
    'piano',
    'pickle',
    'pilot',
    'pine',
    'pixel',
    'planet',
    'plum',
    'polar',
    'pony',
    'poppy',
    'potato',
    'prism',
    'puzzle',
    'quartz',
    'quill',
    'rabbit',
    'radar',
    'radio',
    'rain',
    'raven',
    'reef',
    'ribbon',
    'river',
    'robin',
    'rocket',
    'ruby',
    'saddle',
    'salmon',
    'sandal',
    'saturn',
    'scarf',
    'shadow',
    'shell',
    'silver',
    'sketch',
    'snow',
    'solar',
    'spice',
    'spider',
    'spoon',
    'spruce',
    'squid',
    'stamp',
    'star',
    'stone',
    'storm',
    'sugar',
  ];

  static List<String> generate([Random? random]) {
    final source = random ?? Random.secure();
    return [for (var i = 0; i < count; i++) list[source.nextInt(list.length)]];
  }

  /// The words as typed (any case, spaces, dashes or commas between them)
  /// in canonical form, or null unless they are exactly six known words.
  static String? normalize(String input) {
    final words = input
        .toLowerCase()
        .split(RegExp('[^a-z]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length != count || !words.every(_known.contains)) return null;
    return words.join(' ');
  }

  static final Set<String> _known = list.toSet();
}

/// What "Add a device" shows as a QR code (or a code to paste on a
/// desktop): how to reach the hub, which host key to expect, and the
/// secrets sealed under the six words.
@immutable
class SyncSetupOffer {
  const SyncSetupOffer({
    required this.hubName,
    required this.host,
    required this.port,
    required this.username,
    required this.hostKeyType,
    required this.hostKeyFingerprint,
    required this.hubHostId,
    required this.vaultId,
    required this.salt,
    required this.sealed,
    this.memoryKiB = 19456,
    this.iterations = 2,
  });

  static const prefix = 'conductore-sync:1:';

  final String hubName;
  final String host;
  final int port;
  final String username;
  final String hostKeyType;
  final String hostKeyFingerprint;
  final String hubHostId;
  final String vaultId;
  final Uint8List salt;

  /// Argon2id cost for the words.
  final int memoryKiB;
  final int iterations;

  /// The sealed [SyncSetupSecret].
  final Uint8List sealed;

  Map<String, Object?> _publicJson() => {
    'n': hubName,
    'h': host,
    'p': port,
    'u': username,
    'kt': hostKeyType,
    'fp': hostKeyFingerprint,
    'id': hubHostId,
    'v': vaultId,
    's': base64UrlEncode(salt),
    'm': memoryKiB,
    'i': iterations,
  };

  /// Associated data of the seal: every readable field, so none can be
  /// swapped (another hub, another host key) without the words failing.
  List<int> get associatedData => utf8.encode(canonicalJson(_publicJson()));

  String encode() {
    final json = {..._publicJson(), 'x': base64UrlEncode(sealed)};
    return '$prefix${base64UrlEncode(utf8.encode(jsonEncode(json)))}';
  }

  /// Reads a scanned or pasted code; whitespace (a wrapped paste) is
  /// ignored. Null for anything that is not a Conductore setup code.
  static SyncSetupOffer? decode(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (!compact.startsWith(prefix)) return null;
    try {
      final body = compact.substring(prefix.length);
      final json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(body))),
      );
      if (json is! Map) return null;
      final port = json['p'];
      final memory = json['m'];
      final iterations = json['i'];
      final fields = [json['n'], json['h'], json['u'], json['kt'], json['fp']];
      final ids = [json['id'], json['v']];
      if (port is! int ||
          port < 1 ||
          port > 65535 ||
          memory is! int ||
          iterations is! int ||
          fields.any((f) => f is! String) ||
          ids.any((f) => f is! String || f.isEmpty)) {
        return null;
      }
      return SyncSetupOffer(
        hubName: json['n'] as String,
        host: json['h'] as String,
        port: port,
        username: json['u'] as String,
        hostKeyType: json['kt'] as String,
        hostKeyFingerprint: json['fp'] as String,
        hubHostId: json['id'] as String,
        vaultId: json['v'] as String,
        salt: base64Url.decode(base64Url.normalize(json['s'] as String)),
        sealed: base64Url.decode(base64Url.normalize(json['x'] as String)),
        memoryKiB: memory,
        iterations: iterations,
      );
    } catch (_) {
      return null;
    }
  }
}

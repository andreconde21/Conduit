import 'package:conduit/features/agent_attention/domain/agent_attention.dart';

/// Understands short spoken answers in the Talk loop (English and
/// Portuguese): approval verdicts and question options.
abstract final class VoiceAnswers {
  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"[^\p{L}\p{N}' ]", unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _hasAny(String text, List<String> words) {
    final padded = ' $text ';
    return words.any((word) => padded.contains(' $word '));
  }

  static const _always = ['always', 'always allow', 'sempre'];
  static const _deny = [
    'deny',
    'no',
    'nope',
    'reject',
    'refuse',
    'cancel',
    'stop',
    "don't",
    'do not',
    'não',
    'nao',
    'negar',
    'nega',
    'recusar',
    'recusa',
  ];
  static const _allow = [
    'allow',
    'yes',
    'yeah',
    'yep',
    'ok',
    'okay',
    'approve',
    'sure',
    'go ahead',
    'do it',
    'run it',
    'sim',
    'permitir',
    'permite',
    'aprovar',
    'aprova',
    'pode',
    'claro',
  ];

  /// The verdict in [spoken], or null when it is not clear. "Always" wins,
  /// then any refusal (so "don't allow" is a denial), then consent.
  static PermissionVerdict? verdict(String spoken) {
    final text = _normalize(spoken);
    if (text.isEmpty) return null;
    if (_hasAny(text, _always)) return PermissionVerdict.always;
    if (_hasAny(text, _deny)) return PermissionVerdict.deny;
    if (_hasAny(text, _allow)) return PermissionVerdict.allow;
    return null;
  }

  static const _numbers = <String, int>{
    'one': 1,
    'first': 1,
    'um': 1,
    'uma': 1,
    'primeiro': 1,
    'primeira': 1,
    'two': 2,
    'second': 2,
    'dois': 2,
    'duas': 2,
    'segundo': 2,
    'segunda': 2,
    'three': 3,
    'third': 3,
    'três': 3,
    'tres': 3,
    'terceiro': 3,
    'terceira': 3,
    'four': 4,
    'fourth': 4,
    'quatro': 4,
    'quarto': 4,
    'quarta': 4,
    'five': 5,
    'fifth': 5,
    'cinco': 5,
    'quinto': 5,
    'quinta': 5,
    'six': 6,
    'sixth': 6,
    'seis': 6,
    'sexto': 6,
    'sexta': 6,
    'seven': 7,
    'seventh': 7,
    'sete': 7,
    'sétimo': 7,
    'eight': 8,
    'eighth': 8,
    'oito': 8,
    'oitavo': 8,
    'nine': 9,
    'ninth': 9,
    'nove': 9,
    'nono': 9,
  };

  /// The 1-based option [spoken] picks among [labels] (by number, ordinal
  /// or name), or null when it matches none.
  static int? option(String spoken, List<String> labels) {
    final text = _normalize(spoken);
    if (text.isEmpty || labels.isEmpty) return null;
    // A name first: "SQLite" beats a stray number inside a label.
    for (var i = 0; i < labels.length; i++) {
      final label = _normalize(labels[i]);
      if (label.isNotEmpty && ' $text '.contains(' $label ')) return i + 1;
    }
    for (final word in text.split(' ')) {
      final number = int.tryParse(word) ?? _numbers[word];
      if (number != null && number >= 1 && number <= labels.length) {
        return number;
      }
    }
    for (var i = 0; i < labels.length; i++) {
      final label = _normalize(labels[i]);
      if (text.length >= 3 && label.contains(text)) return i + 1;
    }
    return null;
  }

  static const _more = [
    'more',
    'read more',
    'continue',
    'go on',
    'keep going',
    'keep reading',
    'mais',
    'continua',
    'continuar',
  ];

  /// Whether [spoken] asks to hear the rest of a brief reply ("more",
  /// "read more", "continue"). Only the whole phrase counts: "continue
  /// with the tests" is a prompt.
  static bool isMore(String spoken) => _more.contains(_normalize(spoken));
}

/// A speech language choice: [tag] is BCP-47; an empty tag means the device
/// locale.
class SpeechLanguage {
  const SpeechLanguage(this.tag, this.label);

  final String tag;
  final String label;

  bool get isDeviceDefault => tag.isEmpty;
}

const deviceDefaultSpeechLanguage = SpeechLanguage('', 'Device default');

/// Languages offered in the Speech setting. Any other BCP-47 tag can be
/// typed in; the recognizer decides whether it has the language pack.
const speechLanguages = <SpeechLanguage>[
  deviceDefaultSpeechLanguage,
  SpeechLanguage('en-US', 'English (US)'),
  SpeechLanguage('en-GB', 'English (UK)'),
  SpeechLanguage('pt-PT', 'Português (Portugal)'),
  SpeechLanguage('pt-BR', 'Português (Brasil)'),
  SpeechLanguage('es-ES', 'Español'),
  SpeechLanguage('fr-FR', 'Français'),
  SpeechLanguage('de-DE', 'Deutsch'),
  SpeechLanguage('it-IT', 'Italiano'),
  SpeechLanguage('nl-NL', 'Nederlands'),
];

/// Normalizes a user-typed tag: trims, swaps `_` for `-`, and rejects
/// anything that is not letters/digits/hyphens. Returns null when invalid.
String? normalizeSpeechLanguageTag(String raw) {
  final tag = raw.trim().replaceAll('_', '-');
  if (tag.isEmpty) {
    return '';
  }
  if (!RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$').hasMatch(tag)) {
    return null;
  }
  final parts = tag.split('-');
  return [
    parts.first.toLowerCase(),
    for (final part in parts.skip(1))
      part.length == 2 ? part.toUpperCase() : part,
  ].join('-');
}

/// Human label for a stored tag.
String describeSpeechLanguage(String tag) {
  for (final language in speechLanguages) {
    if (language.tag == tag) {
      return language.label;
    }
  }
  return tag;
}

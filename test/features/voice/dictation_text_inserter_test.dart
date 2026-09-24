import 'package:conduit/features/voice/domain/speech_languages.dart';
import 'package:conduit/features/voice/presentation/dictation_text_inserter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DictationTextInserter', () {
    test('streams partials at the cursor, replacing the previous partial', () {
      final controller = TextEditingController(text: 'fix the ');
      final inserter = DictationTextInserter(controller);

      inserter.begin();
      inserter.partial('login');
      expect(controller.text, 'fix the login');
      inserter.partial('login bug');
      expect(controller.text, 'fix the login bug');
      inserter.finish('login bug please');
      expect(controller.text, 'fix the login bug please');
      expect(controller.selection.baseOffset, controller.text.length);
    });

    test('adds a space after non-whitespace and replaces a selection', () {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'keep THIS end',
          selection: TextSelection(baseOffset: 5, extentOffset: 9),
        ),
      );
      final inserter = DictationTextInserter(controller);

      inserter.begin();
      inserter.partial('that');

      expect(controller.text, 'keep that end');
      expect(controller.selection.baseOffset, 'keep that'.length);
    });

    test('cancel restores the original text; an empty final keeps it', () {
      final controller = TextEditingController(text: 'draft');
      final inserter = DictationTextInserter(controller);

      inserter.begin();
      inserter.partial('noise');
      inserter.cancel();
      expect(controller.text, 'draft');

      inserter.begin();
      inserter.partial('more');
      inserter.finish('');
      expect(controller.text, 'draft');
    });
  });

  group('normalizeSpeechLanguageTag', () {
    test('accepts and normalizes BCP-47 tags', () {
      expect(normalizeSpeechLanguageTag(' pt_pt '), 'pt-PT');
      expect(normalizeSpeechLanguageTag('EN-us'), 'en-US');
      expect(normalizeSpeechLanguageTag('de'), 'de');
      expect(normalizeSpeechLanguageTag(''), '');
    });

    test('rejects garbage', () {
      expect(normalizeSpeechLanguageTag('english'), isNull);
      expect(normalizeSpeechLanguageTag('pt PT'), isNull);
      expect(normalizeSpeechLanguageTag('p'), isNull);
    });

    test('describes stored tags', () {
      expect(describeSpeechLanguage(''), 'Device default');
      expect(describeSpeechLanguage('pt-PT'), 'Português (Portugal)');
      expect(describeSpeechLanguage('xx-YY'), 'xx-YY');
    });
  });
}

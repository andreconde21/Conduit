import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/voice/domain/voice_answers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spoken approval verdicts', () {
    expect(VoiceAnswers.verdict('Allow'), PermissionVerdict.allow);
    expect(VoiceAnswers.verdict('yes, go ahead'), PermissionVerdict.allow);
    expect(VoiceAnswers.verdict('Sim.'), PermissionVerdict.allow);
    expect(VoiceAnswers.verdict('deny'), PermissionVerdict.deny);
    expect(VoiceAnswers.verdict("don't allow that"), PermissionVerdict.deny);
    expect(VoiceAnswers.verdict('não'), PermissionVerdict.deny);
    expect(VoiceAnswers.verdict('always'), PermissionVerdict.always);
    expect(VoiceAnswers.verdict('sempre'), PermissionVerdict.always);
    expect(VoiceAnswers.verdict('what was that'), isNull);
    expect(VoiceAnswers.verdict(''), isNull);
  });

  test('spoken question options by number, ordinal or name', () {
    const labels = ['Postgres', 'SQLite', 'Both of them'];
    expect(VoiceAnswers.option('2', labels), 2);
    expect(VoiceAnswers.option('option two', labels), 2);
    expect(VoiceAnswers.option('the first one', labels), 1);
    expect(VoiceAnswers.option('terceira', labels), 3);
    expect(VoiceAnswers.option('SQLite please', labels), 2);
    expect(VoiceAnswers.option('both', labels), 3);
    expect(VoiceAnswers.option('seven', labels), isNull);
    expect(VoiceAnswers.option('mongo', labels), isNull);
  });
}

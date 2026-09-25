import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/voice/domain/speech_text.dart';
import 'package:flutter_test/flutter_test.dart';

ChatToolCall tool(String name, [Map<String, Object?> input = const {}]) =>
    ChatToolCall(
      'id-$name-${input.hashCode}',
      name: name,
      input: input,
      kind: ChatItemBuilder.toolKind(name),
    );

void main() {
  group('fromMarkdown', () {
    test('drops emphasis, headings and quotes; ends sentences', () {
      expect(
        SpeechText.fromMarkdown(
          '## Summary\n\nThis is **really** _important_ and ~~old~~ new\n'
          '> quoted line',
        ),
        'Summary. This is really important and old new quoted line.',
      );
    });

    test('code blocks become a cue and are never read', () {
      expect(
        SpeechText.fromMarkdown(
          'Run this:\n\n```bash\nrm -rf build\nflutter test\n```\nThen done.',
        ),
        'Run this: Code block. Then done.',
      );
    });

    test('inline code is read as words', () {
      expect(
        SpeechText.fromMarkdown(
          'Call `readAloudController.stop()` in `lib/chat_view_page.dart` '
          'with `--force`.',
        ),
        'Call read Aloud Controller.stop in lib chat view page.dart '
        'with force.',
      );
    });

    test('lists become sentences', () {
      expect(
        SpeechText.fromMarkdown(
          'I changed:\n- the parser\n- the tests!\n1. first step\n'
          '2) second step\n- [x] done task',
        ),
        'I changed: the parser. the tests! first step. second step. '
        'done task.',
      );
    });

    test('links read as their text and bare URLs as their host', () {
      expect(
        SpeechText.fromMarkdown(
          'See [the docs](https://example.com/a) or '
          'https://www.github.com/x/y and <https://dev.azure.com/o>. '
          '![diagram](x.png)',
        ),
        'See the docs or github.com and dev.azure.com. diagram.',
      );
    });

    test('tables become one cue and rules are skipped', () {
      expect(
        SpeechText.fromMarkdown(
          'Results\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n---\n\nAll good',
        ),
        'Results. Table. All good.',
      );
    });

    test('snake case outside code is not treated as emphasis', () {
      expect(
        SpeechText.inline('set max_session_ms now'),
        'set max_session_ms now',
      );
    });
  });

  test('chunk splits long text at sentence ends under the cap', () {
    final text = List.filled(30, 'This is one sentence of text.').join(' ');
    final chunks = SpeechText.chunk(text, max: 100);
    expect(chunks.every((c) => c.length <= 100), isTrue);
    expect(chunks.join(' '), text);
    expect(chunks.first, endsWith('.'));
  });

  test('cap cuts long answers at a sentence and points to the screen', () {
    expect(SpeechText.cap('Short answer.'), 'Short answer.');
    final long = List.filled(40, 'This sentence is filler text.').join(' ');
    final capped = SpeechText.cap(long);
    expect(capped.length, lessThan(SpeechText.maxAnswer + 40));
    expect(capped, endsWith('filler text. …the rest is on screen.'));
  });

  test('finalAnswer is the text after the last tool call', () {
    const intro = ChatAssistantText('a1', text: 'Let me check.');
    const outro1 = ChatAssistantText('a2', text: 'All fixed.');
    const outro2 = ChatAssistantText('a3', text: 'Tests pass.');
    expect(
      SpeechText.finalAnswer([
        const ChatUserMessage('u', text: 'fix it'),
        intro,
        tool('Bash', {'command': 'make'}),
        const ChatThinking('t'),
        outro1,
        outro2,
      ]),
      [outro1, outro2],
    );
    expect(
      SpeechText.finalAnswer([
        intro,
        tool('Bash', {'command': 'make'}),
      ]),
      isEmpty,
    );
  });

  test('approval announcement names the tool and summary', () {
    expect(
      SpeechText.approval(
        const PendingPermissionRequest(
          id: 'r1',
          toolName: 'Bash',
          summary: 'npm test',
        ),
      ),
      'Claude needs your approval to run npm test.',
    );
    expect(
      SpeechText.approval(
        const PendingPermissionRequest(
          id: 'r2',
          toolName: 'Edit',
          summary: 'src/app.ts',
        ),
        hint: true,
      ),
      'Claude needs your approval to edit src/app.ts. '
      'Say allow, deny, or always.',
    );
  });

  test('question announcement reads the question and options', () {
    expect(
      SpeechText.question(
        const ChatQuestion(
          'q',
          questions: [
            ChatQuestionPrompt(
              question: 'Which database?',
              options: [
                ChatQuestionOption(label: 'Postgres'),
                ChatQuestionOption(label: 'SQLite'),
              ],
            ),
          ],
        ),
      ),
      'Claude is asking: Which database? Options: Postgres, or SQLite.',
    );
    expect(
      SpeechText.question(
        const ChatQuestion(
          'q',
          questions: [
            ChatQuestionPrompt(
              question: 'Which database?',
              options: [
                ChatQuestionOption(label: 'Postgres'),
                ChatQuestionOption(label: 'SQLite'),
              ],
            ),
          ],
        ),
        hint: true,
      ),
      'Claude is asking: Which database? Options: 1, Postgres; 2, SQLite. '
      'Say the number or the name.',
    );
  });
}

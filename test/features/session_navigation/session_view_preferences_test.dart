import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/session_navigation/domain/session_view_preferences.dart';
import 'package:conduit/features/session_navigation/presentation/session_view_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolve', () {
    const chatByDefault = SessionViewPreferences(defaultView: SessionView.chat);

    test('the terminal by default', () {
      const preferences = SessionViewPreferences();
      expect(preferences.resolve('h', runsClaude: true), SessionView.terminal);
    });

    test('the global default for a Claude pane', () {
      expect(chatByDefault.resolve('h', runsClaude: true), SessionView.chat);
    });

    test('a per-session override wins over the default', () {
      final preferences = chatByDefault.withOverride(
        'h#tmux:work',
        SessionView.terminal,
      );
      expect(
        preferences.resolve('h#tmux:work', runsClaude: true),
        SessionView.terminal,
      );
      // Other sessions on the machine keep the default.
      expect(
        preferences.resolve('h#tmux:other', runsClaude: true),
        SessionView.chat,
      );
      final chatHere = const SessionViewPreferences().withOverride(
        'h#tmux:work',
        SessionView.chat,
      );
      expect(
        chatHere.resolve('h#tmux:work', runsClaude: true),
        SessionView.chat,
      );
    });

    test('non-Claude panes and plain shells always open the terminal', () {
      final preferences = chatByDefault.withOverride('h', SessionView.chat);
      expect(preferences.resolve('h', runsClaude: false), SessionView.terminal);
      expect(
        preferences.resolve('h#herdr:w1', runsClaude: false),
        SessionView.terminal,
      );
    });

    test('clearing an override goes back to the default', () {
      final preferences = chatByDefault
          .withOverride('h#tmux:work', SessionView.terminal)
          .withOverride('h#tmux:work', null);
      expect(preferences.overrides, isEmpty);
      expect(
        preferences.resolve('h#tmux:work', runsClaude: true),
        SessionView.chat,
      );
    });
  });

  test('a Herdr session keeps its choice whichever tab a link focused', () {
    expect(sessionViewKey('h#herdr:w1:w1:t2'), 'h#herdr:w1');
    expect(sessionViewKey('h#herdr@s:w1'), 'h#herdr@s:w1');
    expect(sessionViewKey('h#tmux:work'), 'h#tmux:work');
    expect(sessionViewKey('h'), 'h');
    expect(sessionViewKey('h#shell'), 'h');
    final preferences = const SessionViewPreferences().withOverride(
      'h#herdr:w1',
      SessionView.chat,
    );
    expect(
      preferences.resolve('h#herdr:w1:w1:t3', runsClaude: true),
      SessionView.chat,
    );
  });

  test('only Claude agents count as Claude', () {
    AgentInfo agent(String kind) => AgentInfo(
      id: 'a',
      name: 'a',
      state: AgentAttentionState.working,
      kind: kind,
    );
    expect(isClaudeAgent(agent('claude')), isTrue);
    expect(isClaudeAgent(agent('claude-code')), isTrue);
    expect(isClaudeAgent(agent('codex')), isFalse);
    expect(isClaudeAgent(agent('opencode')), isFalse);
  });

  test('JSON round trip, and junk falls back to the defaults', () {
    final preferences = const SessionViewPreferences(
      defaultView: SessionView.chat,
    ).withOverride('h#tmux:work', SessionView.terminal);
    expect(SessionViewPreferences.fromJson(preferences.toJson()), preferences);
    expect(
      SessionViewPreferences.fromJson({'version': 99}),
      const SessionViewPreferences(),
    );
    expect(
      SessionViewPreferences.fromJson({
        'version': 1,
        'default': 'nope',
        'overrides': {'a': 'chat', 'b': 'bogus', 'c': 3},
      }).overrides,
      {'a': SessionView.chat},
    );
  });

  test('the controller loads, saves and notifies', () async {
    final repository = InMemorySessionViewPreferencesRepository(
      const SessionViewPreferences(defaultView: SessionView.chat),
    );
    final controller = SessionViewController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.defaultView, SessionView.chat);

    var notified = 0;
    controller.addListener(() => notified += 1);
    await controller.setOverride('h#tmux:work', SessionView.terminal);
    await controller.setDefaultView(SessionView.terminal);
    expect(notified, 2);
    expect(repository.stored.defaultView, SessionView.terminal);
    expect(repository.stored.overrideFor('h#tmux:work'), SessionView.terminal);
    expect(
      controller.viewFor('h#tmux:work', runsClaude: true),
      SessionView.terminal,
    );
  });
}

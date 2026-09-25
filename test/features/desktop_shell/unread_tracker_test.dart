import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/desktop_shell/domain/unread_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnreadTracker', () {
    late DateTime now;
    late UnreadTracker tracker;

    setUp(() {
      now = DateTime.utc(2026, 9, 25, 12);
      tracker = UnreadTracker(clock: () => now);
    });

    test('the first sight of a row is not news', () {
      expect(tracker.observe('m/a/t/main', 100), isFalse);
      expect(tracker.isUnread('m/a/t/main'), isFalse);
      // Newer activity is.
      expect(tracker.observe('m/a/t/main', 200), isTrue);
      expect(tracker.isUnread('m/a/t/main'), isTrue);
      // Older or equal activity changes nothing.
      expect(tracker.observe('m/a/t/main', 150), isFalse);
    });

    test('viewing clears a row, and activity while on screen is read', () {
      tracker
        ..observe('m/a/t/main', 100)
        ..observe('m/a/t/main', 200);
      expect(tracker.setViewed({'m/a/t/main'}), isTrue);
      expect(tracker.isUnread('m/a/t/main'), isFalse);
      expect(tracker.observe('m/a/t/main', 300), isFalse);
      expect(tracker.isUnread('m/a/t/main'), isFalse);
      tracker.setViewed({});
      tracker.observe('m/a/t/main', 400);
      expect(tracker.isUnread('m/a/t/main'), isTrue);
    });

    test('viewing a workspace covers its tabs and panes', () {
      tracker
        ..observeState('m/a/h/w1/t/t1/p/p1', 'working')
        ..observeState('m/a/h/w1/t/t1/p/p1', 'finished');
      expect(tracker.isUnread('m/a/h/w1/t/t1/p/p1'), isTrue);
      tracker.setViewed({'m/a/h/w1'});
      expect(tracker.isUnread('m/a/h/w1/t/t1/p/p1'), isFalse);
    });

    test('agent states: finishing and needing input are news, working not', () {
      const key = 'm/a/h/w1/p/p1';
      tracker.observeState(key, 'idle');
      expect(tracker.isUnread(key), isFalse);
      now = now.add(const Duration(seconds: 1));
      tracker.observeState(
        key,
        'working',
        news: agentStateIsNews(AgentAttentionState.working),
      );
      expect(tracker.isUnread(key), isFalse);
      now = now.add(const Duration(seconds: 1));
      tracker.observeState(
        key,
        'finished',
        news: agentStateIsNews(AgentAttentionState.finished),
      );
      expect(tracker.isUnread(key), isTrue);
      tracker.markRead(key);
      now = now.add(const Duration(seconds: 1));
      tracker.observeState(
        key,
        'needsInput',
        news: agentStateIsNews(AgentAttentionState.needsInput),
      );
      expect(tracker.isUnread(key), isTrue);
    });

    test('mark as read covers descendants; mark as unread sticks', () {
      tracker
        ..observe('m/a/t/x', 1)
        ..observe('m/a/t/x', 2)
        ..observe('m/a/t/x/w/1', 1)
        ..observe('m/a/t/x/w/1', 2);
      expect(tracker.unreadKeys, {'m/a/t/x', 'm/a/t/x/w/1'});
      tracker.markRead('m/a');
      expect(tracker.unreadKeys, isEmpty);
      tracker.markUnread('m/a/t/x');
      expect(tracker.isUnread('m/a/t/x'), isTrue);
      tracker.setViewed({'m/a/t/x'});
      expect(tracker.isUnread('m/a/t/x'), isFalse);
    });

    test('state survives a restart', () {
      final mark = now.millisecondsSinceEpoch;
      tracker
        ..observe('m/a/t/x', mark - 2)
        ..observe('m/a/t/x', mark - 1)
        ..observeState('m/a/h/w/p/p', 'idle')
        ..markUnread('m/b');
      final json = tracker.toJson();
      final restored = UnreadTracker(clock: () => now)..load(json);
      expect(restored.isUnread('m/a/t/x'), isTrue);
      expect(restored.isUnread('m/b'), isTrue);
      // A state that changed while the app was closed is news.
      now = now.add(const Duration(minutes: 5));
      restored.observeState('m/a/h/w/p/p', 'finished');
      expect(restored.isUnread('m/a/h/w/p/p'), isTrue);
    });

    test('old entries are dropped when saving', () {
      tracker
        ..observe('old', 1)
        ..observe('old', 2)
        ..observe('new', now.millisecondsSinceEpoch)
        ..observe('new', now.millisecondsSinceEpoch + 1);
      final json = tracker.toJson();
      final activity = json['activity']! as Map;
      expect(activity.keys, ['new']);
    });
  });
}

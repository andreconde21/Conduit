import 'package:conduit/features/usage/domain/usage_report.dart';

/// The "near your limit" notification for the Claude 5-hour window.
class UsageAlert {
  const UsageAlert({
    required this.title,
    required this.body,
    required this.window,
  });

  /// Notification id: one alert at a time, a new one replaces it.
  static const notificationId = 'usage-5h';

  final String title;
  final String body;

  /// Identifies the window alerted for (its reset time), so each window
  /// alerts once.
  final DateTime window;
}

/// Decides when the 80 % alert fires: once per 5-hour window, when the
/// window's use first reaches [threshold].
class UsageAlertPolicy {
  const UsageAlertPolicy({this.threshold = 80});

  final double threshold;

  /// Two reports of one window may differ slightly in their reset time.
  static const _sameWindow = Duration(minutes: 5);

  /// The alert to show now, or null. [alerted] is the window of the last
  /// alert (see [UsageAlert.window]).
  UsageAlert? evaluate({
    required UsageLimit? fiveHour,
    required DateTime now,
    required DateTime? alerted,
  }) {
    if (fiveHour == null || fiveHour.effectivePct(now) < threshold) {
      return null;
    }
    // Without a reset time, the window is taken to end 5 h from now.
    final window = fiveHour.resetsAt ?? now.add(const Duration(hours: 5));
    if (alerted != null) {
      final sameWindow =
          window.difference(alerted).abs() <= _sameWindow ||
          (fiveHour.resetsAt == null && now.isBefore(alerted));
      if (sameWindow) {
        return null;
      }
    }
    final pct = fiveHour.effectivePct(now).floor();
    final reset = fiveHour.resetsAt;
    return UsageAlert(
      title: 'Claude usage at $pct%',
      body: reset == null
          ? '$pct% of your 5-hour window used.'
          : '$pct% of your 5-hour window used, resets at '
                '${formatClockTime(reset)}.',
      window: window,
    );
  }
}

/// `14:05` in local time.
String formatClockTime(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

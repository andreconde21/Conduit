import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/core/telemetry/telemetry.dart';
import 'package:flutter/material.dart';

/// What the one-time notice and the Privacy section say, word for word.
const privacyNoticeText =
    'Conductore sends crash reports and anonymous usage counts to help fix '
    'bugs. Nothing from your machines or terminals is included.';

const crashReportsCaption =
    "When something breaks, the error and the app's own code lines go to "
    "Outsmartis' GlitchTip server. Machine names, addresses, users, "
    'commands and terminal text are removed first.';

const usageStatsCaption =
    'Counts of screens opened and connections made (SSH or Mosh, worked or '
    "failed) go to Outsmartis' Plausible server. No identifiers, nothing "
    'from your machines or terminals.';

/// Settings › Privacy: the two switches, stored on this device and applied
/// at once.
class PrivacySettingsControls extends StatelessWidget {
  const PrivacySettingsControls({required this.telemetry, super.key});

  final Telemetry telemetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: telemetry,
      builder: (context, _) {
        final preferences = telemetry.preferences;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSwitchCard(
              switchKey: const ValueKey('privacy-crash-reports'),
              icon: Icons.bug_report_outlined,
              title: 'Send crash reports',
              subtitle: crashReportsCaption,
              value: preferences.crashReports,
              onChanged: telemetry.setCrashReports,
            ),
            const SizedBox(height: 14),
            SettingsSwitchCard(
              switchKey: const ValueKey('privacy-usage-stats'),
              icon: Icons.insights_outlined,
              title: 'Send anonymous usage stats',
              subtitle: usageStatsCaption,
              value: preferences.usageStats,
              onChanged: telemetry.setUsageStats,
            ),
            const SizedBox(height: 14),
            Text(
              telemetry.config.sendEnabled
                  ? 'Kept on this device, never synced. The privacy policy '
                        '(docs/privacy-policy.md) lists every field sent.'
                  : 'This is a development build: it sends nothing, '
                        'whatever the switches say.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'dart:async';

import 'package:conduit/core/platform_features.dart';
import 'package:conduit/core/telemetry/telemetry.dart';
import 'package:conduit/features/settings/presentation/privacy_settings.dart';
import 'package:conduit/features/settings/presentation/settings_catalog.dart';
import 'package:conduit/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';

/// The one-time notice about crash reports and usage counts, on home until
/// "OK" or "Settings" dismisses it; then it takes no space at all.
///
/// A compact card on phones, a one-row banner on desktops.
class PrivacyNotice extends StatelessWidget {
  const PrivacyNotice({this.telemetry, super.key});

  /// Defaults to [Telemetry.instance].
  final Telemetry? telemetry;

  @override
  Widget build(BuildContext context) {
    final telemetry = this.telemetry ?? Telemetry.instance;
    return ListenableBuilder(
      listenable: telemetry,
      builder: (context, _) {
        if (!telemetry.showNotice) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        void ok() => unawaited(telemetry.dismissNotice());
        void settings() {
          unawaited(telemetry.dismissNotice());
          unawaited(showSettings(context, section: SettingsSection.privacy));
        }

        final actions = [
          TextButton(
            key: const ValueKey('privacy-notice-settings'),
            onPressed: settings,
            child: const Text('Settings'),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            key: const ValueKey('privacy-notice-ok'),
            onPressed: ok,
            child: const Text('OK'),
          ),
        ];
        final text = Text(privacyNoticeText, style: theme.textTheme.bodyMedium);
        final icon = Icon(
          Icons.privacy_tip_outlined,
          color: colorScheme.primary,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Material(
            key: const ValueKey('privacy-notice'),
            color: colorScheme.surface,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
              child: PlatformFeatures.isDesktop
                  ? Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: text),
                        const SizedBox(width: 12),
                        ...actions,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: icon,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: text),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions,
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

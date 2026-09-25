import 'package:conduit/core/presentation/adaptive_modal.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/hosts/domain/multiplexer_prefix_key.dart';
import 'package:flutter/material.dart';

/// Form field showing the host's multiplexer prefix; tapping it opens
/// [showMultiplexerPrefixPicker].
class MultiplexerPrefixField extends StatelessWidget {
  const MultiplexerPrefixField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final MultiplexerPrefixKey value;
  final ValueChanged<MultiplexerPrefixKey> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: const ValueKey('multiplexer-prefix-field'),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      onTap: () async {
        final picked = await showMultiplexerPrefixPicker(
          context: context,
          initial: value,
        );
        if (picked != null && picked != value) {
          onChanged(picked);
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Multiplexer prefix (tmux/Herdr)',
          helperText:
              'Sent before every tmux and Herdr shortcut: the Tmux, Tmux+ and '
              'Herdr keys, the Herdr navigator and swipe window switching.',
          helperMaxLines: 3,
          prefixIcon: Icon(Icons.keyboard_command_key_rounded),
          suffixIcon: Icon(Icons.chevron_right_rounded),
        ),
        child: Text(value.label, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}

/// Lets the user compose any modifier combination plus one key. Resolves to
/// the chosen prefix, or null when dismissed.
Future<MultiplexerPrefixKey?> showMultiplexerPrefixPicker({
  required BuildContext context,
  required MultiplexerPrefixKey initial,
}) {
  return showAdaptiveModal<MultiplexerPrefixKey>(
    kind: AdaptiveModalKind.dialog,
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => MultiplexerPrefixPickerSheet(initial: initial),
  );
}

class MultiplexerPrefixPickerSheet extends StatefulWidget {
  const MultiplexerPrefixPickerSheet({required this.initial, super.key});

  final MultiplexerPrefixKey initial;

  @override
  State<MultiplexerPrefixPickerSheet> createState() =>
      _MultiplexerPrefixPickerSheetState();
}

class _MultiplexerPrefixPickerSheetState
    extends State<MultiplexerPrefixPickerSheet> {
  late MultiplexerPrefixKey _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = shouldApplyBottomSafeArea(context)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Multiplexer prefix',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'The key tmux and Herdr wait for before a shortcut. Match what '
              'the machine is configured with (`set -g prefix` in tmux).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Container(
                  key: const ValueKey('prefix-preview'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.keyboard_command_key_rounded, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _value.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!_value.hasModifier)
                        Text(
                          'no modifier',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Presets', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in MultiplexerPrefixKey.presets)
                      ChoiceChip(
                        key: ValueKey('prefix-preset-${preset.encode()}'),
                        label: Text(preset.label),
                        selected: _value == preset,
                        onSelected: (_) => setState(() => _value = preset),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Modifiers', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      key: const ValueKey('prefix-mod-ctrl'),
                      label: const Text('Ctrl'),
                      selected: _value.ctrl,
                      onSelected: (selected) => setState(
                        () => _value = _value.copyWith(ctrl: selected),
                      ),
                    ),
                    FilterChip(
                      key: const ValueKey('prefix-mod-alt'),
                      label: const Text('Alt'),
                      selected: _value.alt,
                      onSelected: (selected) => setState(
                        () => _value = _value.copyWith(alt: selected),
                      ),
                    ),
                    FilterChip(
                      key: const ValueKey('prefix-mod-shift'),
                      label: const Text('Shift'),
                      selected: _value.shift,
                      onSelected: (selected) => setState(
                        () => _value = _value.copyWith(shift: selected),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Key', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final key in MultiplexerPrefixKey.allKeys)
                      ChoiceChip(
                        key: ValueKey('prefix-key-$key'),
                        label: Text(
                          MultiplexerPrefixKey(key: key).keyLabel,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        visualDensity: VisualDensity.compact,
                        selected: _value.key == key,
                        onSelected: (_) =>
                            setState(() => _value = _value.copyWith(key: key)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('prefix-save'),
                    onPressed: () => Navigator.of(context).pop(_value),
                    child: Text('Use ${_value.label}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/voice/domain/speech_languages.dart';
import 'package:flutter/material.dart';

/// The "Speech" settings card: which language dictation listens in.
class SpeechSettingsControls extends StatelessWidget {
  const SpeechSettingsControls({required this.controller, super.key});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.mic_none_rounded),
        title: const Text('Language'),
        subtitle: Text(
          'Dictation in Chat mode uses on-device recognition.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              describeSpeechLanguage(controller.speechLanguage),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () => showSpeechLanguageDialog(
          context: context,
          current: controller.speechLanguage,
          onChanged: controller.setSpeechLanguage,
        ),
      ),
    );
  }
}

Future<void> showSpeechLanguageDialog({
  required BuildContext context,
  required String current,
  required ValueChanged<String> onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _SpeechLanguageDialog(current: current, onChanged: onChanged),
  );
}

class _SpeechLanguageDialog extends StatefulWidget {
  const _SpeechLanguageDialog({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  @override
  State<_SpeechLanguageDialog> createState() => _SpeechLanguageDialogState();
}

class _SpeechLanguageDialogState extends State<_SpeechLanguageDialog> {
  static const _custom = '__custom__';

  late String _selection;
  late final TextEditingController _customController;
  String? _customError;

  bool get _isListed =>
      speechLanguages.any((language) => language.tag == widget.current);

  @override
  void initState() {
    super.initState();
    _selection = _isListed ? widget.current : _custom;
    _customController = TextEditingController(
      text: _isListed ? '' : widget.current,
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _apply() {
    if (_selection == _custom) {
      final normalized = normalizeSpeechLanguageTag(_customController.text);
      if (normalized == null) {
        setState(() => _customError = 'Use a tag such as pt-PT or en-US.');
        return;
      }
      widget.onChanged(normalized);
    } else {
      widget.onChanged(_selection);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Speech language'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            RadioGroup<String>(
              groupValue: _selection,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selection = value);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final language in speechLanguages)
                    RadioListTile<String>(
                      value: language.tag,
                      title: Text(language.label),
                      subtitle: language.isDeviceDefault
                          ? null
                          : Text(language.tag),
                      dense: true,
                    ),
                  const RadioListTile<String>(
                    value: _custom,
                    title: Text('Other'),
                    dense: true,
                  ),
                ],
              ),
            ),
            if (_selection == _custom)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  controller: _customController,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Language tag',
                    hintText: 'pt-PT',
                    errorText: _customError,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (_customError != null) {
                      setState(() => _customError = null);
                    }
                  },
                  onSubmitted: (_) => _apply(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Use')),
      ],
    );
  }
}

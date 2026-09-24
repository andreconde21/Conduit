import 'package:flutter/material.dart';

/// Asks whether unsaved edits to [fileName] may be thrown away.
///
/// Resolves to true when the user chooses to discard.
Future<bool> confirmDiscardChanges(
  BuildContext context, {
  required String fileName,
}) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard changes?'),
      content: Text('Unsaved edits to $fileName will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return discard ?? false;
}

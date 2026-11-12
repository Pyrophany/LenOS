import 'package:flutter/material.dart';

import 'file_system_model.dart';

/// Asks for a single line of text. Returns null if cancelled.
///
/// [validator] returns an error message to show, or null if the input is OK.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirmLabel = 'OK',
  String? Function(String)? validator,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      title: title,
      initial: initial,
      confirmLabel: confirmLabel,
      validator: validator,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
    this.validator,
  });

  final String title;
  final String initial;
  final String confirmLabel;
  final String? Function(String)? validator;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select the name but not the extension, like most file managers.
    final dot = widget.initial.lastIndexOf('.');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : widget.initial.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Asks the user to confirm an action. Returns true if confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Lets the user pick a destination folder. Folders in [exclude] (and
/// anything inside them) are not offered. Returns null if cancelled.
Future<String?> pickFolder(
  BuildContext context,
  FileSystemModel fs, {
  String title = 'Move to',
  String? exclude,
}) {
  final folders = fs
      .allFolders()
      .where((d) =>
          exclude == null || (d != exclude && !d.startsWith('$exclude/')))
      .toList();
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final folder in folders)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(folder),
            child: Row(
              children: [
                const Icon(Icons.folder, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(folder)),
              ],
            ),
          ),
      ],
    ),
  );
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(error.toString())));
}

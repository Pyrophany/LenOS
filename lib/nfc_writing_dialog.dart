import 'package:flutter/material.dart';

import 'nfc_model.dart';

/// Tells the user NFC writing is on and waits for [write]. Pops with true on
/// success, the error on failure, or null if cancelled.
class NfcWritingDialog extends StatefulWidget {
  const NfcWritingDialog({
    super.key,
    required this.label,
    required this.write,
    required this.onCancel,
    this.message,
  });

  final String label;

  /// Replaces the default "Hold [label] near the phone…" text.
  final String? message;
  final Future<String> write;
  final VoidCallback onCancel;

  @override
  State<NfcWritingDialog> createState() => _NfcWritingDialogState();
}

class _NfcWritingDialogState extends State<NfcWritingDialog> {
  @override
  void initState() {
    super.initState();
    widget.write.then<Object?>((_) => true, onError: (Object e) {
      return e is NfcWriteCancelled ? null : e;
    }).then((outcome) {
      if (mounted) Navigator.of(context).pop(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.nfc, size: 40),
      title: const Text('NFC writing enabled'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message ?? 'Hold ${widget.label} near the phone to write your changes.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

/// Shows [NfcWritingDialog] for [write]. Returns true on success, the
/// [NfcWriteException] (or other error) on failure, or null if cancelled.
Future<Object?> showNfcWritingDialog(
  BuildContext context, {
  required String label,
  required Future<String> write,
  required VoidCallback onCancel,
  String? message,
}) =>
    showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NfcWritingDialog(
          label: label, write: write, onCancel: onCancel, message: message),
    );

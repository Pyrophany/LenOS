import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'fractionate.dart';
import 'fs/record_codec.dart';
import 'nfc_model.dart';
import 'terminal_settings.dart';
import 'terminal_style.dart';
import 'user.dart';

/// A unix-like terminal. Each command entered becomes a Terminal style file
/// (`[USER]@LenOS:~$ Command`) that is appended to the next NFC device scanned,
/// after the files already on it.
///
/// `fractionate` instead holds the next device and alternately sends and
/// deletes a `trance` command every 2 s until the device leaves range
/// (speeding up with the dynamic intervals setting).
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

enum _LineKind { command, info, success, error }

class _Line {
  const _Line(this.text, this.kind);
  final String text;
  final _LineKind kind;
}

class _TerminalPageState extends State<TerminalPage> {
  static const _font = TerminalStyle.font;

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _lines = <_Line>[];
  late final NfcModel _nfc;
  bool _writing = false;

  /// Set while `fractionate` holds a device; [_stop] ends it after its step.
  bool _holding = false;
  bool _stop = false;

  @override
  void initState() {
    super.initState();
    _nfc = context.read<NfcModel>();
  }

  @override
  void dispose() {
    // Leaving the terminal drops a write that has not found a device yet,
    // and ends fractionate after its current step.
    _stop = true;
    if (_writing) _nfc.cancelWrite();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _prompt(String user) => '$user@LenOS:~\$';

  /// `fractionate` or `sudo fractionate`, with or without anything after it
  /// (e.g. `fractionate --test`). Extra arguments are ignored for now.
  static bool _isFractionate(String command) =>
      RegExp(r'^(sudo\s+)?fractionate(\s|$)').hasMatch(command.trim());

  /// Whether [command] starts with the word `sudo` (`sudo`, `sudo ls`, ...).
  static bool _isSudo(String command) =>
      RegExp(r'^sudo(\s|$)').hasMatch(command.trim());

  void _print(String text, _LineKind kind) {
    setState(() => _lines.add(_Line(text, kind)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _submit() async {
    if (_writing) return;
    final command = _input.text.trim();
    // sudo commands run as root, so they are written as root@LenOS.
    final user = _isSudo(command) ? 'root' : context.read<LenOSUser>().name;
    final line = '${_prompt(user)} $command';
    _input.clear();
    _focus.requestFocus();
    _print(line, _LineKind.command);
    if (command.isEmpty) return;

    setState(() => _writing = true);
    _print('Searching for NFC device... hold it near the phone.', _LineKind.info);
    if (_isFractionate(command)) return _fractionate(user);
    try {
      // The Terminal is the one writer that keeps earlier Terminal inputs.
      final uid = await _nfc.appendToNextTag(
        [RecordCodec.terminalRecord(line)],
        keepTerminalInputs: true,
      );
      if (mounted) _print('Written to device $uid.', _LineKind.success);
    } on NfcWriteCancelled {
      if (mounted) _print('^C  Write cancelled.', _LineKind.info);
    } catch (e) {
      if (mounted) _print('Write failed: $e', _LineKind.error);
    } finally {
      if (mounted) {
        setState(() => _writing = false);
        _focus.requestFocus();
      }
    }
  }

  /// Holds the next device and runs [fractionate] on it, sending `trance`
  /// as [user].
  Future<void> _fractionate(String user) async {
    _stop = false;
    final trance = RecordCodec.terminalRecord('${_prompt(user)} trance');
    final intervalFor = context.read<TerminalSettings>().dynamicIntervals
        ? tranceInterval
        : fixedTranceInterval;
    void log(String message) {
      if (mounted) _print(message, _LineKind.info);
    }

    var sent = 0;
    try {
      final uid = await _nfc.holdNextTag((tag) async {
        if (mounted) setState(() => _holding = true);
        log('Holding device ${tag.uid}. Keep it in range.');
        sent = await fractionate(tag, trance,
            intervalFor: intervalFor, stopped: () => _stop, log: log);
      });
      if (mounted) {
        _print('Fractionated device $uid: trance sent $sent time(s).',
            _LineKind.success);
      }
    } on NfcWriteCancelled {
      if (mounted) _print('^C  Write cancelled.', _LineKind.info);
    } catch (e) {
      if (mounted) _print('Fractionate failed: $e', _LineKind.error);
    } finally {
      if (mounted) {
        setState(() {
          _writing = false;
          _holding = false;
        });
        _focus.requestFocus();
      }
    }
  }

  void _cancel() {
    _stop = true;
    _nfc.cancelWrite();
  }

  static Color _colorOf(TerminalStyle ts, _LineKind kind) => switch (kind) {
        _LineKind.command => ts.text,
        _LineKind.info => ts.dim,
        _LineKind.success => ts.accent,
        _LineKind.error => ts.error,
      };

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    final user = context.watch<LenOSUser>().name;
    return Scaffold(
      backgroundColor: ts.background,
      appBar: AppBar(
        title: const Text('Terminal'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear_all),
            onPressed: _lines.isEmpty ? null : () => setState(_lines.clear),
          ),
        ],
      ),
      body: GestureDetector(
        // Tapping anywhere on the terminal focuses the input, like a real one.
        onTap: _focus.requestFocus,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                itemCount: _lines.length,
                itemBuilder: (context, i) => SelectableText(
                  _lines[i].text,
                  style: _font.copyWith(color: _colorOf(ts, _lines[i].kind)),
                ),
              ),
            ),
            if (_writing)
              _SearchingBar(
                label: _holding
                    ? 'Fractionating: keep the device in range'
                    : 'Waiting for NFC device',
                onCancel: _cancel,
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    Text('${_prompt(user)} ',
                        style: _font.copyWith(color: ts.accent)),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        autofocus: true,
                        readOnly: _writing,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.send,
                        // _submit() refocuses, so the keyboard stays open between commands.
                        onSubmitted: (_) => _submit(),
                        style: _font.copyWith(color: ts.text),
                        cursorColor: ts.accent,
                        decoration: const InputDecoration.collapsed(hintText: ''),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Send',
                      color: ts.text,
                      disabledColor: ts.faint,
                      icon: const Icon(Icons.send),
                      onPressed: _writing ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchingBar extends StatelessWidget {
  const _SearchingBar({required this.label, required this.onCancel});

  final String label;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    return Column(
      children: [
        const LinearProgressIndicator(minHeight: 2),
        Container(
          color: ts.raised,
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              Icon(Icons.nfc, color: ts.dim, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: TextStyle(color: ts.dim)),
              ),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
        ),
      ],
    );
  }
}

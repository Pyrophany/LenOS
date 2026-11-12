import 'package:flutter/material.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:provider/provider.dart';

import 'file_manager_page.dart';
import 'fs/editor_session.dart';
import 'fs/file_system_model.dart';
import 'fs/fs_dialogs.dart';
import 'fs/record_codec.dart';
import 'loaded_files_page.dart';
import 'terminal_style.dart';

enum _MenuAction { newFile, save, rename, export, import, open }

/// Tabbed code editor showing the files open in the [EditorSession], styled
/// like the Terminal.
///
/// Callers open files in the session first (`openFile` / `newFile`) and then
/// push this page. Leaving the page keeps every tab open, unsaved edits
/// included; only closing a tab asks about unsaved changes.
class CodeEditorPage extends StatelessWidget {
  const CodeEditorPage({super.key, this.returnTo});

  /// Set when a device file was opened from Devices: saving [buffer] pops
  /// this page with its text, so the device page can replace the file.
  /// [label] names the device file, e.g. `alpha · File 2`.
  final ({EditorBuffer buffer, String label})? returnTo;

  bool _returnsToDevice(EditorBuffer? b) => b != null && returnTo?.buffer == b;

  static bool _canSave(EditorSession session, EditorBuffer? b) =>
      b != null &&
      !b.binary &&
      !session.isMissing(b) &&
      (b.dirty || b.fileId == null);

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    final session = context.watch<EditorSession>();
    context.watch<FileSystemModel>(); // Renames and deletes update the tabs.
    final active = session.active;

    return Scaffold(
      backgroundColor: ts.background,
      appBar: AppBar(
        title: const Text('LenOS Code'),
        actions: [
          PopupMenuButton<_MenuAction>(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onSelected: (action) => _onMenu(context, action),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _MenuAction.newFile,
                child: ListTile(
                  leading: Icon(Icons.note_add),
                  title: Text('New File'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.save,
                enabled: _canSave(session, active),
                child: ListTile(
                  leading: const Icon(Icons.save),
                  title: const Text('Save File'),
                  subtitle: _returnsToDevice(active)
                      ? Text('Back to ${returnTo!.label}')
                      : null,
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.rename,
                enabled: active != null && !session.isMissing(active),
                child: const ListTile(
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('Rename File'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.export,
                enabled: active != null && !session.isMissing(active),
                child: const ListTile(
                  leading: Icon(Icons.upload),
                  title: Text('Export File'),
                  subtitle: Text('To a device'),
                ),
              ),
              const PopupMenuItem(
                value: _MenuAction.import,
                child: ListTile(
                  leading: Icon(Icons.nfc),
                  title: Text('Import File'),
                  subtitle: Text('From Devices'),
                ),
              ),
              const PopupMenuItem(
                value: _MenuAction.open,
                child: ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('Open File'),
                  subtitle: Text('From File Manager'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Theme(
        data: Theme.of(context),
        child: active == null
            ? _NoFilesOpen(onNew: () => session.newFile())
            : Column(
                children: [
                  _TabStrip(session: session),
                  if (_returnsToDevice(active))
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      color: ts.raised,
                      child: Text(
                        'Editing ${returnTo!.label}. Save returns it to the device list.',
                        style: TerminalStyle.font.copyWith(
                          fontSize: 12,
                          color: ts.accent,
                        ),
                      ),
                    ),
                  Expanded(
                    child: IndexedStack(
                      // Every tab stays built so it keeps its scroll position,
                      // selection and undo history while hidden.
                      index: session.activeIndex,
                      children: [
                        for (final b in session.buffers)
                          _BufferView(key: ObjectKey(b), buffer: b),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, _MenuAction action) async {
    final session = context.read<EditorSession>();
    switch (action) {
      case _MenuAction.newFile:
        session.newFile(folder: session.active?.folder ?? '/');
      case _MenuAction.save:
        final active = session.active;
        if (active == null) return;
        if (_returnsToDevice(active)) {
          // A device file with no File Manager copy: offer to save one
          // first. Cancelling still sends it back to the device.
          if (active.fileId == null) {
            await saveBuffer(context, active, fromDevice: true);
            if (!context.mounted) return;
          }
          return _saveToDevice(context, active);
        }
        await saveBuffer(context, active);
      case _MenuAction.rename:
        final active = session.active;
        if (active != null) await renameBuffer(context, active);
      case _MenuAction.export:
        final active = session.active;
        if (active == null || session.isMissing(active)) return;
        final NdefRecord record;
        try {
          // Binary tabs are read-only, so their file is exported as-is.
          record = active.binary
              ? session.fileOf(active)!.record
              : session.buildRecord(active);
        } catch (e) {
          if (context.mounted) {
            showError(context, 'Cannot export this file: $e');
          }
          return;
        }
        if (RecordCodec.isTerminalInput(record)) {
          showError(
            context,
            'Terminal commands are removed from devices automatically. '
            'Send them from the Terminal instead.',
          );
          return;
        }
        final device = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => LoadedFilesPage(exportRecord: record),
          ),
        );
        if (device != null && context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Exported ${session.nameOf(active)} to $device.'),
              ),
            );
        }
      case _MenuAction.import:
        final picked = await Navigator.of(context).push<PickedDeviceFile>(
          MaterialPageRoute(
            builder: (_) => const LoadedFilesPage(pickFile: true),
          ),
        );
        final text = picked == null
            ? null
            : RecordCodec.decodeText(picked.record);
        if (picked != null && text != null) {
          session.importText(text, name: picked.name);
        }
      case _MenuAction.open:
        final id = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => const FileManagerPage(pickFile: true),
          ),
        );
        if (id != null) session.openFile(id);
    }
  }
}

/// Sends [b]'s text back to the device page that opened it. A File Manager
/// file is saved there too; a tab without one is closed, since its content
/// now lives in the device's list.
void _saveToDevice(BuildContext context, EditorBuffer b) {
  final session = context.read<EditorSession>();
  if (b.fileId != null) {
    try {
      session.save(b);
    } on FileSystemException catch (e) {
      showError(context, e);
      return;
    }
  }
  final text = b.controller.text;
  if (b.fileId == null) session.close(b);
  Navigator.of(context).pop(text);
}

/// Saves [b], asking for a name and folder if it is a new file.
/// [fromDevice] says in the dialog that cancelling still saves to the device.
/// Returns true on success.
Future<bool> saveBuffer(
  BuildContext context,
  EditorBuffer b, {
  bool fromDevice = false,
}) async {
  final session = context.read<EditorSession>();
  try {
    if (b.fileId == null) {
      final target = await showDialog<({String name, String folder})>(
        context: context,
        builder: (_) =>
            _SaveAsDialog(session: session, buffer: b, fromDevice: fromDevice),
      );
      if (target == null) return false;
      session.saveAs(b, target.name, folder: target.folder);
    } else {
      session.save(b);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${session.fileOf(b)?.path ?? session.nameOf(b)}',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
    }
    return true;
  } on FileSystemException catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// Asks for a new name for [b]'s file (or unsaved tab) and applies it.
Future<void> renameBuffer(BuildContext context, EditorBuffer b) async {
  final session = context.read<EditorSession>();
  if (session.isMissing(b)) return;
  final file = session.fileOf(b);
  final current = session.nameOf(b);
  final name = await promptText(
    context,
    title: 'Rename file',
    initial: current,
    confirmLabel: 'Rename',
    validator: (n) {
      final error = FileSystemModel.validateName(n);
      if (error != null) return error;
      if (n != current &&
          file != null &&
          session.fs.exists(FileSystemModel.join(file.folder, n))) {
        return 'A file or folder with this name already exists';
      }
      return null;
    },
  );
  if (name == null || name == current || !context.mounted) return;
  try {
    session.rename(b, name);
  } on FileSystemException catch (e) {
    showError(context, e);
  }
}

/// Asks where in the File Manager to save a new file: a folder and a name.
class _SaveAsDialog extends StatefulWidget {
  const _SaveAsDialog({
    required this.session,
    required this.buffer,
    this.fromDevice = false,
  });

  final EditorSession session;
  final EditorBuffer buffer;

  /// The file is going back to a device either way.
  final bool fromDevice;

  @override
  State<_SaveAsDialog> createState() => _SaveAsDialogState();
}

class _SaveAsDialogState extends State<_SaveAsDialog> {
  late final _name = TextEditingController(
    text: widget.session.nameOf(widget.buffer),
  );
  late final _folders = widget.session.fs.allFolders();
  late String _folder = _folders.contains(widget.buffer.folder)
      ? widget.buffer.folder
      : '/';
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select the name but not the extension.
    final dot = _name.text.lastIndexOf('.');
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : _name.text.length,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    var error = FileSystemModel.validateName(name);
    if (error == null &&
        widget.session.fs.exists(FileSystemModel.join(_folder, name))) {
      error = 'A file or folder with this name already exists';
    }
    if (error != null) return setState(() => _error = error);
    Navigator.of(context).pop((name: name, folder: _folder));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save to File Manager'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.fromDevice) ...[
            const Text(
              'This file is not in the File Manager yet. Save a copy here, or '
              'Cancel to only save it to the device.',
            ),
            const SizedBox(height: 8),
          ],
          DropdownButtonFormField<String>(
            initialValue: _folder,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Folder'),
            items: [
              for (final f in _folders)
                DropdownMenuItem(
                  value: f,
                  child: Text(f, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (f) => setState(() {
              _folder = f ?? '/';
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Closes a tab, offering to save it first if it has unsaved changes.
Future<void> closeBuffer(BuildContext context, EditorBuffer b) async {
  final session = context.read<EditorSession>();
  if (!b.dirty || session.isMissing(b)) return session.close(b);

  session.activate(session.buffers.indexOf(b));
  final choice = await showDialog<_UnsavedChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: Text('Save changes to ${session.nameOf(b)} before closing?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedChoice.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedChoice.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case _UnsavedChoice.save:
      if (await saveBuffer(context, b)) session.close(b);
    case _UnsavedChoice.discard:
      session.close(b);
    case _UnsavedChoice.cancel:
    case null:
      break;
  }
}

enum _UnsavedChoice { save, discard, cancel }

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.session});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    final buffers = session.buffers;
    return Container(
      height: 44,
      color: ts.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: buffers.length,
        itemBuilder: (context, i) {
          final b = buffers[i];
          final selected = i == session.activeIndex;
          final name = session.nameOf(b);
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
            child: InputChip(
              label: Text(
                b.dirty ? '• $name' : name,
                style: TerminalStyle.font.copyWith(
                  fontSize: 13,
                  color: selected ? ts.text : ts.dim,
                  decoration: session.isMissing(b)
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              selected: selected,
              showCheckmark: false,
              backgroundColor: ts.surface,
              selectedColor: ts.raised,
              side: BorderSide(color: selected ? ts.accent : ts.faint),
              deleteIconColor: ts.dim,
              // Tapping the tab that is already open renames its file.
              onPressed: selected
                  ? (session.isMissing(b)
                        ? null
                        : () => renameBuffer(context, b))
                  : () => session.activate(i),
              tooltip: selected && !session.isMissing(b)
                  ? 'Tap to rename'
                  : null,
              onDeleted: () => closeBuffer(context, b),
              deleteButtonTooltipMessage: 'Close',
            ),
          );
        },
      ),
    );
  }
}

class _BufferView extends StatelessWidget {
  const _BufferView({super.key, required this.buffer});

  final EditorBuffer buffer;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    final session = context.read<EditorSession>();
    final file = session.fileOf(buffer);

    if (session.isMissing(buffer)) {
      return Center(
        child: Text(
          'This file was deleted.',
          style: TerminalStyle.font.copyWith(color: ts.dim),
        ),
      );
    }

    int? size;
    try {
      size = buffer.binary
          ? file?.record.byteLength
          : session.buildRecord(buffer).byteLength;
    } catch (_) {
      size = null;
    }

    return Column(
      children: [
        if (buffer.binary)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: ts.raised,
            child: Text(
              'Binary record: shown as hex, read-only.',
              style: TerminalStyle.font.copyWith(color: ts.dim),
            ),
          ),
        Expanded(
          child: TextField(
            controller: buffer.controller,
            readOnly: buffer.binary,
            maxLines: null,
            expands: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: TerminalStyle.font.copyWith(color: ts.text),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: ts.surface,
          child: SafeArea(
            top: false,
            child: Text(
              [
                file?.path ??
                    '${FileSystemModel.join(buffer.folder, buffer.untitledName)} (unsaved)',
                _cursorPosition(buffer.controller),
                size == null ? '? bytes' : '$size bytes',
              ].join('  ·  '),
              style: TerminalStyle.font.copyWith(fontSize: 12, color: ts.dim),
            ),
          ),
        ),
      ],
    );
  }

  /// `Ln 3, Col 5` for the caret, 1-based.
  static String _cursorPosition(TextEditingController c) {
    final offset = c.selection.baseOffset.clamp(0, c.text.length);
    final before = c.text.substring(0, offset);
    final line = '\n'.allMatches(before).length + 1;
    final col = offset - (before.lastIndexOf('\n') + 1) + 1;
    return 'Ln $line, Col $col';
  }
}

class _NoFilesOpen extends StatelessWidget {
  const _NoFilesOpen({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No files open',
            style: TerminalStyle.font.copyWith(color: ts.dim),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: ts.accent,
              side: BorderSide(color: ts.accent),
            ),
            onPressed: onNew,
            icon: const Icon(Icons.note_add),
            label: const Text('New File'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:provider/provider.dart';

import 'ascii_cat.dart';
import 'code_editor_page.dart';
import 'device_registry.dart';
import 'file_manager_page.dart';
import 'fs/editor_session.dart';
import 'fs/file_system_model.dart';
import 'fs/fs_dialogs.dart';
import 'fs/len_file.dart';
import 'fs/record_codec.dart';
import 'nfc_model.dart';
import 'nfc_writing_dialog.dart';
import 'settings_page.dart';
import 'terminal_style.dart';

/// A file chosen from a device in picker mode, with a suggested tab name
/// (including the extension).
typedef PickedDeviceFile = ({NdefRecord record, String name});

/// The Devices page: favorite devices with their storage use. Tap one to see its files from
/// the last time it was scanned.
class LoadedFilesPage extends StatelessWidget {
  const LoadedFilesPage({super.key, this.pickFile = false, this.exportRecord})
    : assert(!pickFile || exportRecord == null);

  /// Picker mode: tapping a text file closes Devices with a
  /// [PickedDeviceFile] as the route result.
  final bool pickFile;

  /// Export mode: tapping a device opens it with this file appended. Once it
  /// has been written, Devices closes with the device's label as the result.
  final NdefRecord? exportRecord;

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<DeviceRegistry>();
    final favorites = registry.favorites;

    final Widget? loadWarning = registry.loadError == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _Warning(
              severe: true,
              text:
                  "Saved device data couldn't be read. To protect it, "
                  'nothing will be saved until the app is restarted and can read it.',
              actions: const [],
            ),
          );

    Widget body;
    if (favorites.isEmpty) {
      body = const _NoFavorites();
    } else if (registry.order == DeviceOrder.custom) {
      body = ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        header: loadWarning,
        buildDefaultDragHandles: false,
        itemCount: favorites.length,
        // Gives the final position, already adjusted for the removed item.
        onReorderItem: registry.moveFavorite,
        itemBuilder: (context, i) => _DeviceCard(
          key: ValueKey(favorites[i].uid),
          device: favorites[i],
          dragIndex: i,
          pickFile: pickFile,
          exportRecord: exportRecord,
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ?loadWarning,
          for (final d in favorites)
            _DeviceCard(
              device: d,
              pickFile: pickFile,
              exportRecord: exportRecord,
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pickFile
              ? 'Import from Devices'
              : exportRecord != null
              ? 'Export to which device?'
              : 'Devices',
        ),
        actions: [
          PopupMenuButton<DeviceOrder>(
            tooltip: 'Order devices',
            icon: const Icon(Icons.sort),
            initialValue: registry.order,
            onSelected: (order) => registry.order = order,
            itemBuilder: (_) => [
              for (final order in DeviceOrder.values)
                CheckedPopupMenuItem(
                  value: order,
                  checked: order == registry.order,
                  child: Text(order.label),
                ),
            ],
          ),
        ],
      ),
      body: CatBackdrop(
        child: favorites.isEmpty && loadWarning != null
            ? Column(
                children: [
                  loadWarning,
                  Expanded(child: body),
                ],
              )
            : body,
      ),
    );
  }
}

class _NoFavorites extends StatelessWidget {
  const _NoFavorites();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No favorite devices yet.\n'
              'Star a device in Settings → Scanned devices to see it here.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.nfc),
              label: const Text('Scanned devices'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DevicesPage())),
            ),
          ],
        ),
      ),
    );
  }
}

/// A favorite device with its storage bar underneath.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    super.key,
    required this.device,
    required this.pickFile,
    this.exportRecord,
    this.dragIndex,
  });

  final NfcDevice device;
  final bool pickFile;
  final NdefRecord? exportRecord;

  Future<void> _export(BuildContext context, NdefRecord record) async {
    String? problem;
    if (device.records == null) {
      problem =
          "${device.label}'s files have not been read yet. Scan it first.";
    } else if (device.writeInterrupted) {
      problem =
          'The last write to ${device.label} did not finish. Open it in '
          'Devices to repair it before exporting to it.';
    }
    if (problem != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final written = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DeviceFilesPage(uid: device.uid, appendRecord: record),
      ),
    );
    if (written != null && context.mounted) Navigator.of(context).pop(written);
  }

  /// Set in custom order: shows a drag handle for this list index.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = device.records;
    final fileCount = records == null
        ? 'Contents not read yet'
        : records.length == 1
        ? '1 file'
        : '${records.length} files';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (exportRecord != null) return _export(context, exportRecord!);
          final picked = await Navigator.of(context).push<PickedDeviceFile>(
            MaterialPageRoute(
              builder: (_) =>
                  DeviceFilesPage(uid: device.uid, pickFile: pickFile),
            ),
          );
          if (picked != null && context.mounted) {
            Navigator.of(context).pop(picked);
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.nfc, color: theme.colorScheme.primary, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.label, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (device.name != null) device.uid,
                            fileCount,
                            'Scanned ${formatDate(device.lastSeen)}',
                          ].join(' · '),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (dragIndex != null)
                    ReorderableDragStartListener(
                      index: dragIndex!,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: StorageBar(device: device, large: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Storage used on a device, as a bar with a caption. Pass [used] to show a
/// planned size (e.g. with unsaved changes) instead of the device's current one.
class StorageBar extends StatelessWidget {
  const StorageBar({
    super.key,
    required this.device,
    this.used,
    this.large = false,
  });

  final NfcDevice device;
  final int? used;

  /// Thicker bar and bigger caption, for the Devices list.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = used ?? device.usedBytes;
    final cap = device.capacity;
    final known = bytes != null && cap != null && cap > 0;
    final fraction = known ? bytes / cap : null;
    final nearlyFull = fraction != null && fraction >= 0.9;
    final String caption;
    if (!known) {
      caption = 'Storage unknown: scan this device to update';
    } else if (bytes > cap) {
      caption = 'Over by ${bytes - cap} bytes · $bytes of $cap bytes';
    } else {
      caption = '${(fraction! * 100).round()}% used · $bytes of $cap bytes';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(large ? 7 : 4),
          child: LinearProgressIndicator(
            value: (fraction ?? 0).clamp(0.0, 1.0),
            minHeight: large ? 14 : 8,
            color: nearlyFull ? theme.colorScheme.error : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          used == null ? caption : 'After changes: $caption',
          style:
              (large ? theme.textTheme.bodyMedium : theme.textTheme.bodySmall)
                  ?.copyWith(
                    color: nearlyFull ? theme.colorScheme.error : null,
                  ),
        ),
      ],
    );
  }
}

/// One file in the editable list. [key] stays with the file while it moves.
class _DraftItem {
  _DraftItem(
    this.record,
    this.key, {
    this.edited = false,
    this.deleted = false,
  });
  final NdefRecord record;
  final int key;

  /// Changed in LenOS Code during this draft.
  final bool edited;

  /// Marked for deletion: still listed (outlined red) so it can be undone,
  /// but left out of the size and of what Accept writes.
  final bool deleted;

  _DraftItem copyWith({bool? deleted}) =>
      _DraftItem(record, key, edited: edited, deleted: deleted ?? this.deleted);
}

/// The files a draft will write: everything not marked deleted.
List<NdefRecord> _filesOf(List<_DraftItem> items) => [
  for (final i in items)
    if (!i.deleted) i.record,
];

enum _FileAction { edit, delete, undelete, move }

/// Previews of every file on a device as of its last scan.
///
/// Long-press a file to Edit, Delete or Move it, or use + to add one from the
/// File Manager. Changes are kept as a draft until Accept writes them to the
/// device over NFC (or Cancel drops them).
class DeviceFilesPage extends StatefulWidget {
  const DeviceFilesPage({
    super.key,
    required this.uid,
    this.pickFile = false,
    this.appendRecord,
  }) : assert(!pickFile || appendRecord == null);

  final String uid;

  /// Picker mode: tapping a text file pops with a [PickedDeviceFile].
  /// Nothing can be changed in picker mode.
  final bool pickFile;

  /// Export: opens with this file appended as a draft. After it is written
  /// the page closes with the device's label as the result.
  final NdefRecord? appendRecord;

  @override
  State<DeviceFilesPage> createState() => _DeviceFilesPageState();
}

class _DeviceFilesPageState extends State<DeviceFilesPage> {
  /// The files as they will be written, or null when nothing has changed.
  List<_DraftItem>? _draft;

  /// The device's files when editing started; the write is refused if the
  /// device no longer holds exactly these.
  List<NdefRecord>? _base;

  /// Whether drag handles are shown.
  bool _moving = false;
  int _nextKey = 0;

  /// Draft items with a key from here on were added in this draft.
  int _newFrom = 0;

  /// Repair mode: write the draft even if the device's files can't be read
  /// or don't match [_base]. Only set by the recovery options.
  bool _force = false;

  bool get _editing => _draft != null;

  @override
  void initState() {
    super.initState();
    final record = widget.appendRecord;
    final device = context.read<DeviceRegistry>().byUid(widget.uid);
    if (record == null || device?.records == null || device!.writeInterrupted) {
      return;
    }
    _startEditing(device);
    _draft!.add(_DraftItem(record, _nextKey++));

    final bytes = RecordCodec.messageOf(_filesOf(_draft!)).byteLength;
    final capacity = device.capacity;
    if (capacity != null && bytes > capacity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showError(
          'Not enough storage',
          "This file doesn't fit on ${device.label}: with it the device "
              'would need $bytes bytes, but it holds $capacity. Delete '
              'files to make room, or Cancel.',
        );
      });
    }
  }

  void _startEditing(NfcDevice device) {
    if (_editing) return;
    _base = List.of(device.records!);
    _draft = [for (final r in _base!) _DraftItem(r, _nextKey++)];
    _newFrom = _nextKey;
  }

  /// Starts a draft holding [files] (replacing any current draft), to write
  /// back a backup or repeat an interrupted write.
  void _startRecovery(
    NfcDevice device,
    List<NdefRecord> files, {
    required bool force,
    required String message,
  }) {
    setState(() {
      _base = List.of(device.records ?? const <NdefRecord>[]);
      _draft = [
        // Terminal inputs would be removed on writing anyway.
        for (final r in RecordCodec.withoutTerminalInputs(files))
          _DraftItem(r, _nextKey++),
      ];
      _newFrom = _nextKey; // Nothing is marked NEW in a recovery.
      _moving = false;
      _force = force;
    });
    _showMessage(message);
  }

  void _discard() => setState(() {
    _draft = null;
    _base = null;
    _moving = false;
    _force = false;
  });

  /// The saved File Manager file with the same content as [record], if any.
  static LenFile? _savedMatch(FileSystemModel fs, NdefRecord record) {
    final files = [...fs.files]..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      if (RecordCodec.sameContent(f.record, record)) return f;
    }
    return null;
  }

  String _importName(NfcDevice device, int index, NdefRecord record) =>
      // Device names may contain characters not allowed in file names.
      '${device.label.replaceAll(RegExp(r'[/\s]+'), '-')}-file${index + 1}'
      '.${RecordCodec.extensionFor(record)}';

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showFileMenu(
    NfcDevice device,
    int index,
    _DraftItem item,
    Offset at,
  ) async {
    final record = item.record;
    final fs = context.read<FileSystemModel>();
    final canEdit =
        !item.deleted &&
        (RecordCodec.decodeText(record) != null ||
            _savedMatch(fs, record) != null);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_FileAction>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _FileAction.edit,
          enabled: canEdit,
          child: const ListTile(leading: Icon(Icons.edit), title: Text('Edit')),
        ),
        if (item.deleted)
          const PopupMenuItem(
            value: _FileAction.undelete,
            child: ListTile(
              leading: Icon(Icons.restore),
              title: Text('Undo delete'),
            ),
          )
        else
          const PopupMenuItem(
            value: _FileAction.delete,
            child: ListTile(leading: Icon(Icons.delete), title: Text('Delete')),
          ),
        const PopupMenuItem(
          value: _FileAction.move,
          child: ListTile(leading: Icon(Icons.swap_vert), title: Text('Move')),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _FileAction.edit:
        await _edit(device, index, item);
      case _FileAction.delete:
      case _FileAction.undelete:
        setState(() {
          _startEditing(device);
          _draft![index] = _draft![index].copyWith(
            deleted: action == _FileAction.delete,
          );
        });
      case _FileAction.move:
        // No snack bar here: it would cover the drag handle of the last
        // file, which is where newly added files are. The header says how.
        setState(() {
          _startEditing(device);
          _moving = true;
        });
    }
  }

  /// Opens the file in LenOS Code: its saved copy if one matches, otherwise a
  /// new tab holding its content.
  ///
  /// Saving in the editor comes back here and replaces this file in the list
  /// with the edited one (written to the device on Accept). A matching saved
  /// file is also saved in the File Manager as usual.
  Future<void> _edit(NfcDevice device, int index, _DraftItem item) async {
    final record = item.record;
    final session = context.read<EditorSession>();
    final match = _savedMatch(context.read<FileSystemModel>(), record);
    if (match != null) {
      session.openFile(match.id);
    } else {
      session.importText(
        RecordCodec.decodeText(record)!,
        name: _importName(device, index, record),
      );
    }
    final buffer = session.active!;
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CodeEditorPage(
          returnTo: (
            buffer: buffer,
            label: '${device.label} · File ${index + 1}',
          ),
        ),
      ),
    );
    if (text == null || !mounted || text == RecordCodec.decodeText(record)) {
      return;
    }

    NdefRecord updated;
    try {
      // Keeps the file's kind (text, link, MIME type, ...) as on the device.
      updated = RecordCodec.withText(record, text);
    } on ArgumentError {
      updated =
          match!.record; // Binary on the device: use the saved file's form.
    }
    setState(() {
      final wasEditing = _editing;
      _startEditing(device);
      final i = wasEditing
          ? _draft!.indexWhere((d) => d.key == item.key)
          : index;
      if (i < 0) return;
      _draft![i] = _DraftItem(updated, _draft![i].key, edited: true);
    });
  }

  Future<void> _addFile(NfcDevice device) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FileManagerPage(pickFile: true)),
    );
    if (!mounted || id == null) return;
    final file = context.read<FileSystemModel>().byId(id);
    if (file == null) return;
    setState(() {
      _startEditing(device);
      _draft!.add(_DraftItem(file.record, _nextKey++));
    });
  }

  Future<void> _accept(NfcDevice device) async {
    final files = _filesOf(_draft!);
    final base = _base!;
    // Nothing changed (a repair always writes, since the device may differ).
    if (!_force && RecordCodec.sameRecords(files, base)) return _discard();

    final bytes = RecordCodec.messageOf(files).byteLength;
    final capacity = device.capacity;
    if (capacity != null && bytes > capacity) {
      return _showError(
        'Not enough storage',
        'These changes need $bytes bytes, but ${device.label} holds $capacity. '
            'Delete some files first.',
      );
    }

    final nfc = context.read<NfcModel>();
    final label = device.label;
    final write = nfc.writeToNextTag(
      uid: device.uid,
      force: _force,
      build: (existing) {
        if (_force) return files;
        if (!RecordCodec.sameRecords(existing, base)) {
          throw NfcWriteException(
            'The files on $label changed since it was last scanned, so '
            'nothing was written. Cancel to see its current files, then '
            'make your changes again.',
          );
        }
        return files;
      },
    );
    final outcome = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NfcWritingDialog(
        label: label,
        write: write,
        onCancel: nfc.cancelWrite,
      ),
    );
    if (!mounted) return;
    if (outcome == true) {
      _discard();
      if (widget.appendRecord != null) {
        // Export done: back to the editor, once the page allows leaving again.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(label);
        });
      } else {
        _showMessage('Written to $label.');
      }
    } else if (outcome is NfcWriteException) {
      // If the write broke off partway, Accept now repeats it as a repair.
      if (context.read<DeviceRegistry>().byUid(device.uid)?.writeInterrupted ??
          false) {
        setState(() => _force = true);
      }
      _showError('Write failed', outcome.message);
    }
    // Anything else: cancelled, the draft stays as it was.
  }

  Future<void> _showError(String title, String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<void> _confirmLeave() async {
    final leave = await confirm(
      context,
      title: 'Discard changes?',
      message: 'Your changes have not been written to the device.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (leave && mounted) {
      _discard();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = context.watch<DeviceRegistry>().byUid(widget.uid);
    final fs = context.watch<FileSystemModel>();
    final theme = Theme.of(context);
    if (device == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This device is no longer known.')),
      );
    }
    final records = device.records;
    // While a write is unfinished only the recovery options are offered.
    final canChange =
        !widget.pickFile && records != null && !device.writeInterrupted;
    final items =
        _draft ??
        [
          for (var i = 0; i < (records?.length ?? 0); i++)
            _DraftItem(records![i], i),
        ];
    final draftBytes = _editing
        ? RecordCodec.messageOf(_filesOf(items)).byteLength
        : null;
    final overCapacity =
        draftBytes != null &&
        device.capacity != null &&
        draftBytes > device.capacity!;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.pickFile && device.writeInterrupted)
            _Warning(
              severe: true,
              text:
                  'The last write to this device did not finish, so its '
                  'files may be damaged. Hold it near the phone to check it, '
                  'or choose what to write to it:',
              actions: [
                (
                  label: 'Write again',
                  onPressed: () => _startRecovery(
                    device,
                    device.pendingRecords!,
                    force: true,
                    message: 'The interrupted changes are loaded. Accept to write them.',
                  ),
                ),
                (
                  label: 'Restore previous files',
                  onPressed: () => _startRecovery(
                    device,
                    device.beforeWrite ?? const [],
                    force: true,
                    message: 'The files from before are loaded. Accept to write them.',
                  ),
                ),
              ],
            )
          else if (!widget.pickFile && device.unexpectedlyEmpty)
            _Warning(
              severe: false,
              text:
                  'The last scan found no files, but this device had '
                  '${device.restorableBackup.length} file(s) on '
                  '${formatDate(device.previousRead ?? device.firstSeen)}. If '
                  "that's unexpected, hold it still and scan again, or restore them.",
              actions: [
                (
                  label: 'Restore ${device.restorableBackup.length} file(s)',
                  onPressed: () => _startRecovery(
                    device,
                    device.restorableBackup,
                    force: false,
                    message:
                        'The previous files are loaded. Accept to write them.',
                  ),
                ),
              ],
            ),
          if (device.name != null)
            Text(device.uid, style: theme.textTheme.bodySmall),
          Text(
            device.contentsRead == null
                ? 'Contents have not been read yet.'
                : 'Files as of ${formatDate(device.contentsRead!)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          StorageBar(device: device, used: draftBytes),
          if (canChange && !_editing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Long-press a file to edit, delete or move it.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_moving)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_vert,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Drag the handles to move files, then Accept.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final String? emptyText = records == null
        ? 'Hold this device near the phone to read its files.'
        : _editing && _filesOf(items).isEmpty
        ? 'All files will be removed. Accept to erase this device.'
        : items.isNotEmpty
        ? null
        : 'This device was empty when last scanned.';

    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(device.label),
          actions: [
            if (canChange && device.restorableBackup.isNotEmpty)
              IconButton(
                tooltip: 'Restore previous files',
                icon: const Icon(Icons.history),
                onPressed: () => _startRecovery(
                  device,
                  device.restorableBackup,
                  force: false,
                  message:
                      'Files from '
                      '${formatDate(device.previousRead ?? device.firstSeen)} '
                      'are loaded. Accept to write them, or Cancel.',
                ),
              ),
            if (canChange)
              IconButton(
                tooltip: 'Add file',
                icon: const Icon(Icons.add),
                onPressed: () => _addFile(device),
              ),
          ],
        ),
        body: ReorderableListView.builder(
          // Room below the last file so it can scroll clear of anything
          // shown at the bottom of the screen.
          padding: const EdgeInsets.only(bottom: 96),
          header: header,
          footer: emptyText == null ? null : _Message(emptyText),
          buildDefaultDragHandles: false,
          itemCount: items.length,
          onReorderItem: (from, to) => setState(() {
            _startEditing(device);
            _draft!.insert(to, _draft!.removeAt(from));
          }),
          itemBuilder: (context, i) {
            final item = items[i];
            return _FilePreview(
              key: ValueKey(item.key),
              index: i,
              record: item.record,
              savedName: _savedMatch(fs, item.record)?.name,
              isNew: _editing && item.key >= _newFrom,
              edited: item.edited,
              deleted: item.deleted,
              dragIndex: _moving ? i : null,
              pickName: widget.pickFile
                  ? _importName(device, i, item.record)
                  : null,
              onLongPress: canChange
                  ? (at) => _showFileMenu(device, i, item, at)
                  : null,
            );
          },
        ),
        bottomNavigationBar: _editing
            ? _ConfirmBar(
                error: overCapacity
                    ? 'Too big for this device: $draftBytes of '
                          '${device.capacity} bytes. Delete files to make room.'
                    : null,
                onCancel: _discard,
                onAccept: overCapacity ? null : () => _accept(device),
              )
            : null,
      ),
    );
  }
}

/// A warning box with recovery buttons.
class _Warning extends StatelessWidget {
  const _Warning({
    required this.severe,
    required this.text,
    required this.actions,
  });

  final bool severe;
  final String text;
  final List<({String label, VoidCallback onPressed})> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = severe
        ? theme.colorScheme.errorContainer
        : TerminalStyle.of(context).warning.withValues(alpha: 0.2);
    final foreground = severe
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurface;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                severe ? Icons.error : Icons.warning_amber,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: foreground)),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              for (final a in actions)
                TextButton(onPressed: a.onPressed, child: Text(a.label)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cancel (red) and Accept (green) for pending changes, with an error above
/// them when the changes cannot be written.
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.onCancel,
    required this.onAccept,
    this.error,
  });

  final VoidCallback onCancel;
  final VoidCallback? onAccept;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onAccept,
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(text, textAlign: TextAlign.center),
  );
}

IconData _iconFor(NdefRecord r) {
  if (RecordCodec.isTerminalRecord(r)) return Icons.terminal;
  if (RecordCodec.isUriRecord(r)) return Icons.link;
  if (RecordCodec.isTextRecord(r)) return Icons.description;
  if (RecordCodec.isEditable(r)) return Icons.code;
  return Icons.memory;
}

/// A card showing the start of one file. Tap to expand it in place and
/// scroll through all of it; tap again to collapse.
class _FilePreview extends StatefulWidget {
  const _FilePreview({
    super.key,
    required this.index,
    required this.record,
    this.savedName,
    this.isNew = false,
    this.edited = false,
    this.deleted = false,
    this.dragIndex,
    this.pickName,
    this.onLongPress,
  });

  static const _previewLines = 6;

  /// Tallest an expanded preview gets before it scrolls.
  static const _expandedHeight = 360.0;

  final int index;
  final NdefRecord record;

  /// Name of the saved File Manager file with the same content, if any.
  final String? savedName;

  /// Added in the current draft, not on the device yet.
  final bool isNew;

  /// Changed in LenOS Code, not written to the device yet.
  final bool edited;

  /// Marked for deletion: outlined red until Accept or Undo delete.
  final bool deleted;

  /// Set while moving files: shows a drag handle for this list index.
  final int? dragIndex;

  /// Set in picker mode: tapping returns the file under this name.
  final String? pickName;

  /// Called with the press position to show the file menu.
  final void Function(Offset globalPosition)? onLongPress;

  @override
  State<_FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<_FilePreview> {
  bool _expanded = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onTap(BuildContext context, String? text) {
    final pickName = widget.pickName;
    if (pickName == null) {
      setState(() => _expanded = !_expanded);
    } else if (text == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Binary files can't be imported into the editor."),
          ),
        );
    } else {
      Navigator.of(context)
          .pop<PickedDeviceFile>((record: widget.record, name: pickName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final _FilePreview(
      :index,
      :record,
      :savedName,
      :isNew,
      :edited,
      :deleted,
      :dragIndex,
      :onLongPress,
    ) = widget;
    final theme = Theme.of(context);
    final text = RecordCodec.decodeText(record);
    final preview = text ?? hexDump(record);
    // A named file shows its name in place of its kind (Text, Link, ...).
    final title =
        'File ${index + 1} · ${savedName ?? RecordCodec.describe(record)}';
    final terminal = RecordCodec.isTerminalInput(record);
    final red = theme.colorScheme.error;
    const style = TextStyle(fontFamily: 'monospace', fontSize: 13);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: deleted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: red, width: 2),
            )
          : null,
      child: GestureDetector(
        onLongPressStart: onLongPress == null
            ? null
            : (details) => onLongPress(details.globalPosition),
        child: InkWell(
          onTap: () => _onTap(context, text),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_iconFor(record), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleSmall),
                    ),
                    if (deleted || isNew || edited)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          deleted ? 'DELETED' : (isNew ? 'NEW' : 'EDITED'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: deleted ? red : Colors.green.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Text(
                      '${record.byteLength} B',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (widget.pickName == null)
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                    if (dragIndex != null)
                      ReorderableDragStartListener(
                        index: dragIndex,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                  ],
                ),
                if (terminal)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Terminal command: removed automatically the next time '
                      'LenOS writes to this device.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _expanded
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: _FilePreview._expandedHeight,
                          ),
                          child: Scrollbar(
                            controller: _scroll,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _scroll,
                              child: Text(
                                preview.isEmpty ? '(empty)' : preview,
                                style: style,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          preview.isEmpty ? '(empty)' : preview,
                          maxLines: _FilePreview._previewLines,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

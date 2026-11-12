import 'package:flutter/widgets.dart';
import 'package:nfc_manager/ndef_record.dart';

import 'file_system_model.dart';
import 'len_file.dart';
import 'record_codec.dart';

/// One open tab in the code editor.
class EditorBuffer {
  EditorBuffer._({
    required this.fileId,
    required this.folder,
    required this.untitledName,
    required this.binary,
    required String text,
    String? savedText,
  })  : savedText = savedText ?? text,
        controller = TextEditingController(text: text);

  /// The file this tab edits, or null for an unsaved new file.
  String? fileId;

  /// Folder a new file is saved into (by default).
  String folder;

  /// Name while the tab has no file yet, with extension, e.g. `untitled-2.len`.
  /// It is the suggested name when first saved, and its extension decides
  /// what kind of record the file becomes.
  String untitledName;

  /// Extension of [untitledName] (without the dot), or '' if it has none.
  String get extension {
    final dot = untitledName.lastIndexOf('.');
    return dot > 0 ? untitledName.substring(dot + 1) : '';
  }

  /// Binary records are shown as a read-only hex dump.
  final bool binary;

  final TextEditingController controller;

  /// Text as last saved; the tab is dirty when the editor text differs.
  String savedText;

  bool get dirty => !binary && controller.text != savedText;
}

/// The code editor's open tabs. Lives above the tabs' navigators, so files
/// (including unsaved edits) stay open after leaving the editor page.
class EditorSession extends ChangeNotifier {
  EditorSession(this.fs);

  final FileSystemModel fs;
  final List<EditorBuffer> _buffers = [];
  int _activeIndex = -1;
  int _untitledCounter = 0;

  List<EditorBuffer> get buffers => List.unmodifiable(_buffers);
  int get activeIndex => _activeIndex;
  EditorBuffer? get active =>
      _activeIndex >= 0 ? _buffers[_activeIndex] : null;

  /// The file behind [b], or null if it is unsaved or was deleted.
  LenFile? fileOf(EditorBuffer b) => b.fileId == null ? null : fs.byId(b.fileId!);

  /// True if [b] was saved once but its file has since been deleted.
  bool isMissing(EditorBuffer b) => b.fileId != null && fileOf(b) == null;

  String nameOf(EditorBuffer b) => fileOf(b)?.name ?? b.untitledName;

  /// Opens [fileId] in a tab (or switches to it if already open).
  void openFile(String fileId) {
    final existing = _buffers.indexWhere((b) => b.fileId == fileId);
    if (existing >= 0) return activate(existing);
    final file = fs.byId(fileId);
    if (file == null) return;
    final text = RecordCodec.decodeText(file.record);
    _add(EditorBuffer._(
      fileId: fileId,
      folder: file.folder,
      untitledName: file.name,
      binary: text == null,
      text: text ?? hexDump(file.record),
    ));
  }

  /// Starting content of every new file.
  static const newFileTemplate = 'mixin LenOS-DEVICE\nimport.LenOS: FileType\n{\n}';

  /// Opens an unsaved tab holding [newFileTemplate], saved into [folder].
  void newFile({String folder = '/'}) {
    _untitledCounter++;
    _add(EditorBuffer._(
      fileId: null,
      folder: folder,
      untitledName: 'untitled-$_untitledCounter.len',
      binary: false,
      text: newFileTemplate,
    ));
    // Put the cursor inside the braces, ready to type.
    active!.controller.selection = TextSelection.collapsed(
      offset: newFileTemplate.lastIndexOf('}'),
    );
  }

  /// Opens an unsaved tab with [text] imported from elsewhere (e.g. a device),
  /// named [name] (with extension) until saved. It counts as unsaved, so
  /// closing it asks first.
  void importText(String text, {required String name}) {
    _add(EditorBuffer._(
      fileId: null,
      folder: '/',
      untitledName: name,
      binary: false,
      text: text,
      savedText: '',
    ));
  }

  void _add(EditorBuffer b) {
    b.controller.addListener(notifyListeners); // Keeps dirty markers current.
    _buffers.add(b);
    _activeIndex = _buffers.length - 1;
    notifyListeners();
  }

  void activate(int index) {
    if (index == _activeIndex || index < 0 || index >= _buffers.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Closes a tab without saving. Ask the user first if it is dirty.
  void close(EditorBuffer b) {
    final index = _buffers.indexOf(b);
    if (index < 0) return;
    _buffers.removeAt(index);
    if (_activeIndex >= _buffers.length || index < _activeIndex) _activeIndex--;
    notifyListeners();
    // Dispose after the tab's TextField is gone from the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => b.controller.dispose());
  }

  /// The record [b]'s current text would save as.
  NdefRecord buildRecord(EditorBuffer b, {String? newName}) {
    final file = fileOf(b);
    return file != null
        ? RecordCodec.withText(file.record, b.controller.text)
        : RecordCodec.fromText(
            newName ?? b.untitledName, b.controller.text);
  }

  /// Saves an already-named tab. New tabs use [saveAs].
  void save(EditorBuffer b) {
    fs.updateRecord(b.fileId!, buildRecord(b));
    b.savedText = b.controller.text;
    notifyListeners();
  }

  /// Renames [b]'s file, or just the tab if it is not saved yet.
  /// Throws [FileSystemException] for an invalid or taken name.
  void rename(EditorBuffer b, String name) {
    name = name.trim();
    final error = FileSystemModel.validateName(name);
    if (error != null) throw FileSystemException(error);
    final file = fileOf(b);
    if (file != null) {
      fs.moveFile(file.id, FileSystemModel.join(file.folder, name));
    } else if (isMissing(b)) {
      throw FileSystemException('This file was deleted');
    } else {
      b.untitledName = name;
    }
    notifyListeners();
  }

  /// Creates the file for a new tab, in [folder] if given.
  void saveAs(EditorBuffer b, String name, {String? folder}) {
    if (folder != null) b.folder = folder;
    final file = fs.createFile(
      FileSystemModel.join(b.folder, name),
      buildRecord(b, newName: name),
    );
    b
      ..fileId = file.id
      ..savedText = b.controller.text;
    notifyListeners();
  }
}

/// Read-only hex view of a record that has no text form.
String hexDump(NdefRecord record) {
  final bytes = record.payload;
  final lines = <String>[
    'TNF: ${record.typeNameFormat.name}',
    'Type: ${String.fromCharCodes(record.type)}',
    'Payload (${bytes.length} bytes):',
  ];
  for (var i = 0; i < bytes.length; i += 16) {
    final row = bytes.sublist(i, i + 16 > bytes.length ? bytes.length : i + 16);
    final hex = row.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final text = row
        .map((b) => b >= 0x20 && b < 0x7F ? String.fromCharCode(b) : '.')
        .join();
    lines.add('${i.toRadixString(16).padLeft(4, '0')}  ${hex.padRight(47)}  $text');
  }
  return lines.join('\n');
}

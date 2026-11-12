import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ascii_cat.dart';
import 'code_editor_page.dart';
import 'fs/editor_session.dart';
import 'fs/file_system_model.dart';
import 'fs/fs_dialogs.dart';
import 'fs/len_file.dart';
import 'fs/record_codec.dart';

/// Browses one folder of the LenOS file system. Opening a subfolder pushes
/// another [FileManagerPage], so the back button walks up the tree.
class FileManagerPage extends StatelessWidget {
  const FileManagerPage({super.key, this.folder = '/', this.pickFile = false});

  final String folder;

  /// Picker mode: tapping a file pops every File Manager page with that
  /// file's id as the route result instead of opening it in the editor.
  final bool pickFile;

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FileSystemModel>();
    final title = folder == '/'
        ? (pickFile ? 'Open file' : 'Files')
        : FileSystemModel.nameOf(folder);

    final Widget body;
    if (!fs.isLoaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (fs.loadError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Couldn't open file storage:\n${fs.loadError}",
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (!fs.folderExists(folder)) {
      body = const Center(child: Text('This folder no longer exists.'));
    } else {
      final subfolders = fs.subfoldersOf(folder);
      final files = fs.filesIn(folder);
      body = subfolders.isEmpty && files.isEmpty
          ? const _EmptyFolder()
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final sub in subfolders)
                  _FolderTile(path: sub, pickFile: pickFile),
                for (final file in files)
                  _FileTile(file: file, pickFile: pickFile),
              ],
            );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (folder != '/')
              Text(folder, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: CatBackdrop(child: body),
      floatingActionButton: !pickFile && fs.isLoaded && fs.folderExists(folder)
          ? FloatingActionButton(
              tooltip: 'New',
              onPressed: () => _showNewMenu(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showNewMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add),
              title: const Text('New file'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.read<EditorSession>().newFile(folder: folder);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CodeEditorPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('New folder'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _newFolder(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newFolder(BuildContext context) async {
    final fs = context.read<FileSystemModel>();
    final name = await promptText(
      context,
      title: 'New folder',
      confirmLabel: 'Create',
      validator: FileSystemModel.validateName,
    );
    if (name == null || !context.mounted) return;
    try {
      fs.createFolder(FileSystemModel.join(folder, name));
    } on FileSystemException catch (e) {
      showError(context, e);
    }
  }
}

class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 48, color: color),
          const SizedBox(height: 12),
          Text('This folder is empty', style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

enum _ItemAction { rename, move, delete }

PopupMenuButton<_ItemAction> _itemMenu(void Function(_ItemAction) onSelected) =>
    PopupMenuButton<_ItemAction>(
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(value: _ItemAction.rename, child: Text('Rename')),
        PopupMenuItem(value: _ItemAction.move, child: Text('Move')),
        PopupMenuItem(value: _ItemAction.delete, child: Text('Delete')),
      ],
    );

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.path, required this.pickFile});

  final String path;
  final bool pickFile;

  @override
  Widget build(BuildContext context) {
    final fs = context.read<FileSystemModel>();
    final count = fs.fileCountUnder(path);
    return ListTile(
      leading: const Icon(Icons.folder, color: Colors.amber),
      title: Text(FileSystemModel.nameOf(path)),
      subtitle: Text(count == 1 ? '1 file' : '$count files'),
      onTap: () async {
        final picked = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => FileManagerPage(folder: path, pickFile: pickFile),
          ),
        );
        // Pass a file picked in a subfolder back up to whoever opened the picker.
        if (picked != null && context.mounted) {
          Navigator.of(context).pop(picked);
        }
      },
      trailing: _itemMenu((action) => _onAction(context, action)),
    );
  }

  Future<void> _onAction(BuildContext context, _ItemAction action) async {
    final fs = context.read<FileSystemModel>();
    try {
      switch (action) {
        case _ItemAction.rename:
          final name = await promptText(
            context,
            title: 'Rename folder',
            initial: FileSystemModel.nameOf(path),
            confirmLabel: 'Rename',
            validator: FileSystemModel.validateName,
          );
          if (name == null) return;
          fs.moveFolder(
            path,
            FileSystemModel.join(FileSystemModel.parentOf(path), name),
          );
        case _ItemAction.move:
          final dest = await pickFolder(context, fs, exclude: path);
          if (dest == null) return;
          fs.moveFolder(
            path,
            FileSystemModel.join(dest, FileSystemModel.nameOf(path)),
          );
        case _ItemAction.delete:
          final count = fs.fileCountUnder(path);
          final ok = await confirm(
            context,
            title: 'Delete folder?',
            message: count == 0
                ? '"${FileSystemModel.nameOf(path)}" will be deleted.'
                : '"${FileSystemModel.nameOf(path)}" and the $count '
                      'file${count == 1 ? '' : 's'} inside it will be deleted.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (ok) fs.deleteFolder(path);
      }
    } on FileSystemException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.pickFile});

  final LenFile file;
  final bool pickFile;

  static IconData _iconFor(LenFile file) {
    final r = file.record;
    if (RecordCodec.isUriRecord(r)) return Icons.link;
    if (RecordCodec.isTextRecord(r)) return Icons.description;
    if (RecordCodec.isEditable(r)) return Icons.code;
    return Icons.memory;
  }

  @override
  Widget build(BuildContext context) {
    final size = file.record.byteLength;
    return ListTile(
      leading: Icon(_iconFor(file)),
      title: Text(file.name),
      subtitle: Text('$size bytes · ${_formatDate(file.modified)}'),
      onTap: () {
        if (pickFile) return Navigator.of(context).pop(file.id);
        context.read<EditorSession>().openFile(file.id);
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const CodeEditorPage()));
      },
      trailing: _itemMenu((action) => _onAction(context, action)),
    );
  }

  Future<void> _onAction(BuildContext context, _ItemAction action) async {
    final fs = context.read<FileSystemModel>();
    try {
      switch (action) {
        case _ItemAction.rename:
          final name = await promptText(
            context,
            title: 'Rename file',
            initial: file.name,
            confirmLabel: 'Rename',
            validator: FileSystemModel.validateName,
          );
          if (name == null) return;
          fs.moveFile(file.id, FileSystemModel.join(file.folder, name));
        case _ItemAction.move:
          final dest = await pickFolder(context, fs);
          if (dest == null) return;
          fs.moveFile(file.id, FileSystemModel.join(dest, file.name));
        case _ItemAction.delete:
          final ok = await confirm(
            context,
            title: 'Delete file?',
            message: '"${file.name}" will be deleted.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (ok) fs.deleteFile(file.id);
      }
    } on FileSystemException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

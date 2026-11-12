import 'dart:convert';

import 'package:nfc_manager/ndef_record.dart';

/// One "file" in the LenOS file system: an NDEF record stored under a path.
///
/// Files are not real files on disk; [FileSystemModel] keeps them in a list
/// and saves that list as JSON. The full record is kept so it can be written
/// back to a tag unchanged.
class LenFile {
  LenFile({
    required this.id,
    required this.path,
    required this.record,
    required this.created,
    required this.modified,
    this.sourceUid,
  });

  final String id;

  /// Absolute path, e.g. `/notes/hello.txt`. Folders are implied by it.
  String path;

  NdefRecord record;

  /// UID of the tag this record was saved from, if any.
  final String? sourceUid;

  final DateTime created;
  DateTime modified;

  String get name => path.substring(path.lastIndexOf('/') + 1);

  /// Folder containing this file, e.g. `/notes` (root is `/`).
  String get folder {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'path': path,
        'tnf': record.typeNameFormat.name,
        'type': base64.encode(record.type),
        'identifier': base64.encode(record.identifier),
        'payload': base64.encode(record.payload),
        'sourceUid': sourceUid,
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
      };

  factory LenFile.fromJson(Map<String, Object?> json) => LenFile(
        id: json['id'] as String,
        path: json['path'] as String,
        record: NdefRecord(
          typeNameFormat: TypeNameFormat.values.byName(json['tnf'] as String),
          type: base64.decode(json['type'] as String),
          identifier: base64.decode(json['identifier'] as String),
          payload: base64.decode(json['payload'] as String),
        ),
        sourceUid: json['sourceUid'] as String?,
        created: DateTime.parse(json['created'] as String),
        modified: DateTime.parse(json['modified'] as String),
      );
}

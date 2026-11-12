import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;

import 'package:nfc_manager/ndef_record.dart';

import '../headspace.dart';

/// Converts between NDEF records and the text shown in the code editor.
///
/// Supported as text:
/// - Well-known Text records (`T`) -> `.txt`
/// - Well-known URI records (`U`) -> `.url`
/// - Media records with a textual MIME type (`text/*`, JSON, XML, ...)
///
/// Everything else is binary and has no text form.
class RecordCodec {
  RecordCodec._();

  static final _textType = Uint8List.fromList([0x54]); // 'T'
  static final _uriType = Uint8List.fromList([0x55]); // 'U'

  /// URI identifier codes from the NFC Forum URI RTD (index = code).
  static const uriPrefixes = <String>[
    '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:',
    'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://',
    'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://', 'news:', 'telnet://',
    'imap:', 'rtsp://', 'urn:', 'pop:', 'sip:', 'sips:', 'tftp:', 'btspp://',
    'btl2cap://', 'btgoep://', 'tcpobex://', 'irdaobex://', 'file://',
    'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:',
    'urn:nfc:',
  ];

  /// JSON form of a record, for saving it to storage.
  static Map<String, Object?> toJson(NdefRecord r) => {
        'tnf': r.typeNameFormat.name,
        'type': base64.encode(r.type),
        'identifier': base64.encode(r.identifier),
        'payload': base64.encode(r.payload),
      };

  static NdefRecord fromJson(Map<String, Object?> json) => NdefRecord(
        typeNameFormat: TypeNameFormat.values.byName(json['tnf'] as String),
        type: base64.decode(json['type'] as String),
        identifier: base64.decode(json['identifier'] as String),
        payload: base64.decode(json['payload'] as String),
      );

  /// Whether two records are exactly the same (kind, type, id and payload).
  static bool sameRecord(NdefRecord a, NdefRecord b) =>
      a.typeNameFormat == b.typeNameFormat &&
      listEquals(a.type, b.type) &&
      listEquals(a.identifier, b.identifier) &&
      listEquals(a.payload, b.payload);

  static bool sameRecords(List<NdefRecord> a, List<NdefRecord> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameRecord(a[i], b[i])) return false;
    }
    return true;
  }

  /// Whether two files hold the same content: the same text if both are
  /// text, otherwise the same type and bytes.
  static bool sameContent(NdefRecord a, NdefRecord b) {
    final ta = decodeText(a);
    final tb = decodeText(b);
    if (ta != null && tb != null) return ta == tb;
    return a.typeNameFormat == b.typeNameFormat &&
        listEquals(a.type, b.type) &&
        listEquals(a.payload, b.payload);
  }

  /// An empty NDEF record. Tags cannot hold a message with no records, so a
  /// device with no files gets one of these.
  static final emptyRecord = NdefRecord(
    typeNameFormat: TypeNameFormat.empty,
    type: Uint8List(0),
    identifier: Uint8List(0),
    payload: Uint8List(0),
  );

  /// The files in [records]: everything except empty placeholder records.
  static List<NdefRecord> filesOf(List<NdefRecord> records) =>
      records.where((r) => r.typeNameFormat != TypeNameFormat.empty).toList();

  /// The message to write so a device holds exactly [files].
  static NdefMessage messageOf(List<NdefRecord> files) =>
      NdefMessage(records: files.isEmpty ? [emptyRecord] : files);

  /// A short human description of what kind of file [r] is.
  static String describe(NdefRecord r) {
    if (isTerminalRecord(r)) return 'Terminal command';
    if (Headspace.isHeadspaceRecord(r)) return 'Headspace';
    if (isTextRecord(r)) return 'Text';
    if (isUriRecord(r)) return 'Link';
    final mime = mimeType(r);
    if (mime != null) return mime;
    if (r.typeNameFormat == TypeNameFormat.empty) return 'Empty record';
    final type = ascii.decode(r.type, allowInvalid: true);
    return type.isEmpty
        ? 'Binary (${r.typeNameFormat.name})'
        : 'Binary ($type)';
  }

  /// MIME type of LenOS source files (`.len`), as made by LenOS Code.
  static const lenosMime = 'text/x-lenos';

  /// MIME type of Terminal style files (`[USER]@LenOS:~$ Command`).
  static const terminalMime = 'text/x-lenos-terminal';

  /// A Terminal style file containing [line].
  static NdefRecord terminalRecord(String line) => _mediaRecord(terminalMime, line);

  static bool isTerminalRecord(NdefRecord r) => mimeType(r) == terminalMime;

  /// `name@LenOS:~$ command` on a single line.
  static final _terminalSyntax = RegExp(r'^[^\s@:$/~]+@LenOS:~\$ [^\n]*$');

  /// Whether [r] is a Terminal input: a Terminal style file, or any text file
  /// holding exactly one line of Terminal syntax. These are removed from a
  /// device whenever the app writes to it, except by the Terminal.
  static bool isTerminalInput(NdefRecord r) {
    if (isTerminalRecord(r)) return true;
    final text = decodeText(r);
    return text != null && _terminalSyntax.hasMatch(text.trim());
  }

  /// [records] without any Terminal inputs.
  static List<NdefRecord> withoutTerminalInputs(List<NdefRecord> records) =>
      records.where((r) => !isTerminalInput(r)).toList();

  /// File extension -> MIME type for new files stored as media records.
  /// `.txt` and `.url` are not here: they become Text and URI records.
  static const mimeByExtension = <String, String>{
    'len': lenosMime,
    'trm': terminalMime,
    'json': 'application/json',
    'xml': 'application/xml',
    'html': 'text/html',
    'htm': 'text/html',
    'css': 'text/css',
    'csv': 'text/csv',
    'md': 'text/markdown',
    'js': 'text/javascript',
  };

  static const _textualMimes = {
    'application/json',
    'application/xml',
    'application/javascript',
  };

  static bool _isWellKnown(NdefRecord r, Uint8List type) =>
      r.typeNameFormat == TypeNameFormat.wellKnown &&
      r.type.length == type.length &&
      r.type.first == type.first;

  static bool isTextRecord(NdefRecord r) => _isWellKnown(r, _textType);
  static bool isUriRecord(NdefRecord r) => _isWellKnown(r, _uriType);

  static String? mimeType(NdefRecord r) =>
      r.typeNameFormat == TypeNameFormat.media
          ? ascii.decode(r.type, allowInvalid: true).toLowerCase()
          : null;

  static bool _isTextualMime(String mime) =>
      mime.startsWith('text/') ||
      _textualMimes.contains(mime) ||
      mime.endsWith('+json') ||
      mime.endsWith('+xml');

  /// Whether [r] can be shown and edited as text.
  static bool isEditable(NdefRecord r) => decodeText(r) != null;

  /// The editable text of [r], or null if it is binary or malformed.
  static String? decodeText(NdefRecord r) {
    try {
      if (isTextRecord(r)) return _decodeTextPayload(r.payload);
      if (isUriRecord(r)) return _decodeUriPayload(r.payload);
      final mime = mimeType(r);
      if (mime != null && _isTextualMime(mime)) return utf8.decode(r.payload);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
    return null;
  }

  /// A suggested file extension (without the dot) for [r]. Terminal inputs
  /// are `trm`; other plain text is suggested as a LenOS file (`len`).
  static String extensionFor(NdefRecord r) {
    if (isTerminalInput(r)) return 'trm';
    if (isTextRecord(r)) return 'len';
    if (isUriRecord(r)) return 'url';
    final mime = mimeType(r);
    if (mime != null) {
      for (final e in mimeByExtension.entries) {
        if (e.value == mime) return e.key;
      }
      if (_isTextualMime(mime)) return 'len';
    }
    return 'bin';
  }

  /// Builds the record for a new file named [fileName], choosing the record
  /// kind from its extension (unknown extensions become `text/plain`).
  static NdefRecord fromText(String fileName, String text) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case '':
      case 'txt':
        return _textRecord(text, 'en');
      case 'url':
        return _uriRecord(text);
      default:
        return _mediaRecord(mimeByExtension[ext] ?? 'text/plain', text);
    }
  }

  /// Returns [original] with its content replaced by [text], keeping the
  /// record kind (and language code / MIME type / identifier).
  static NdefRecord withText(NdefRecord original, String text) {
    final NdefRecord updated;
    if (isTextRecord(original)) {
      updated = _textRecord(text, _textLanguage(original.payload));
    } else if (isUriRecord(original)) {
      updated = _uriRecord(text);
    } else {
      final mime = mimeType(original);
      if (mime == null || !_isTextualMime(mime)) {
        throw ArgumentError('Record is not editable as text.');
      }
      updated = _mediaRecord(mime, text);
    }
    return NdefRecord(
      typeNameFormat: updated.typeNameFormat,
      type: updated.type,
      identifier: original.identifier,
      payload: updated.payload,
    );
  }

  // --- Text records -------------------------------------------------------

  static String _decodeTextPayload(Uint8List p) {
    final status = p[0];
    final isUtf16 = status & 0x80 != 0;
    final langLength = status & 0x3F;
    final body = p.sublist(1 + langLength);
    return isUtf16 ? _decodeUtf16(body) : utf8.decode(body);
  }

  static String _textLanguage(Uint8List p) {
    if (p.isEmpty) return 'en';
    final langLength = p[0] & 0x3F;
    if (p.length < 1 + langLength) return 'en';
    return ascii.decode(p.sublist(1, 1 + langLength), allowInvalid: true);
  }

  static String _decodeUtf16(Uint8List bytes) {
    var littleEndian = false;
    var start = 0;
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        littleEndian = true;
        start = 2;
      } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        start = 2;
      }
    }
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  static NdefRecord _textRecord(String text, String language) {
    final lang = ascii.encode(language);
    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: _textType,
      identifier: Uint8List(0),
      // Status byte: UTF-8 (bit 7 clear) + language code length.
      payload: Uint8List.fromList([lang.length & 0x3F, ...lang, ...utf8.encode(text)]),
    );
  }

  // --- URI records --------------------------------------------------------

  static String _decodeUriPayload(Uint8List p) {
    final code = p[0];
    final prefix = code < uriPrefixes.length ? uriPrefixes[code] : '';
    return prefix + utf8.decode(p.sublist(1));
  }

  static NdefRecord _uriRecord(String uri) {
    final trimmed = uri.trim();
    var code = 0;
    for (var i = 1; i < uriPrefixes.length; i++) {
      if (trimmed.startsWith(uriPrefixes[i]) &&
          uriPrefixes[i].length > uriPrefixes[code].length) {
        code = i;
      }
    }
    final rest = trimmed.substring(uriPrefixes[code].length);
    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: _uriType,
      identifier: Uint8List(0),
      payload: Uint8List.fromList([code, ...utf8.encode(rest)]),
    );
  }

  // --- Media records ------------------------------------------------------

  static NdefRecord _mediaRecord(String mime, String text) => NdefRecord(
        typeNameFormat: TypeNameFormat.media,
        type: Uint8List.fromList(ascii.encode(mime)),
        identifier: Uint8List(0),
        payload: Uint8List.fromList(utf8.encode(text)),
      );
}

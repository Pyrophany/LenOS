import 'package:nfc_manager/ndef_record.dart';

import 'device_registry.dart';
import 'fs/record_codec.dart';

/// A Headspace package, stored as the first file on the INTERFACE device:
///
/// ```
/// mixin LenOS-INTERFACE
/// import.LenOS:Headspace
/// {
/// Headspace:Template
/// Traits:[Trait1],[Trait2],[Trait3]
/// Modifier:(none)
/// }
/// ```
class Headspace {
  Headspace({
    required this.name,
    required this.traits,
    this.modifier = '',
    this.comments = '',
  }) : assert(traits.length == traitCount);

  static const traitCount = 3;
  static const header = 'mixin LenOS-INTERFACE';

  /// First lines accepted when reading a Headspace file. [header] is the one
  /// written; the spec's examples use `mixin LenOS-DEVICE`.
  static const acceptedHeaders = [header, 'mixin LenOS-DEVICE'];
  static const importLine = 'import.LenOS:Headspace';

  /// Written when there is no modifier.
  static const noModifier = 'none';

  final String name;
  final List<String> traits;

  /// Behavioral modifier; blank means none.
  final String modifier;

  /// Free text, one comment per line, written after the package as `//` lines.
  final String comments;

  /// [text] as comment lines: each non-blank line gets `//` in front, unless
  /// it already starts with `//`.
  static List<String> commentLines(String text) => [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty)
            line.trimLeft().startsWith('//') ? line.trim() : '//${line.trim()}',
      ];

  /// The file's text, in the Headspace format.
  String toText() {
    final mod = modifier.trim().isEmpty ? noModifier : modifier.trim();
    return [
      header,
      importLine,
      '{',
      'Headspace:${name.trim()}',
      'Traits:${traits.map((t) => '[${t.trim()}]').join(',')}',
      'Modifier:($mod)',
      '}',
      ...commentLines(comments),
    ].join('\n');
  }

  /// The Headspace file as a LenOS (`.len`) record.
  NdefRecord toRecord() => RecordCodec.fromText('headspace.len', toText());

  /// Returns an error message if [value] cannot be used as the Headspace name
  /// or a Trait (it would break the format), else null.
  static String? validatePart(String value, {required String what}) {
    final v = value.trim();
    if (v.isEmpty) return '$what is required';
    if (v.contains('\n')) return '$what must be one line';
    if (RegExp(r'[\[\](){},]').hasMatch(v)) return '$what cannot contain [ ] ( ) { } ,';
    return null;
  }

  static String? validateModifier(String value) {
    final v = value.trim();
    if (v.contains('\n')) return 'Modifier must be one line';
    if (RegExp(r'[(){}]').hasMatch(v)) return 'Modifier cannot contain ( ) { }';
    return null;
  }

  /// Whether [text] is a Headspace file: the LenOS header and the Headspace
  /// import as its first two lines (ignoring blank lines and `//` comments).
  ///
  /// The match ignores case, extra spaces (`import.LenOS: Headspace`, as in
  /// the spec's example), a `{` on the same line, and invisible characters
  /// such as a byte order mark or non-breaking spaces.
  static bool isHeadspaceText(String text) {
    final lines = _meaningfulLines(text).map(_signature).toList();
    return lines.length >= 2 &&
        acceptedHeaders.any((h) => lines[0] == _signature(h)) &&
        lines[1] == _signature(importLine);
  }

  /// [line] reduced to what matters when comparing the header lines.
  static String _signature(String line) {
    var s = line
        .replaceAll(RegExp('[\uFEFF\u200B-\u200D\u2060]'), '')
        .replaceAll(RegExp('[\u00A0\u2000-\u200A\u202F\u205F\u3000]'), ' ')
        .trim()
        .toLowerCase();
    if (s.endsWith('{')) s = s.substring(0, s.length - 1).trimRight();
    s = s.replaceAllMapped(RegExp(r'\s*([.:\-])\s*'), (m) => m[1]!);
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Why [r] is not a Headspace file, quoting its first lines, for messages.
  static String mismatchReason(NdefRecord r) {
    final text = RecordCodec.decodeText(r);
    if (text == null) {
      return 'It is a ${RecordCodec.describe(r)} file, not text.';
    }
    final lines = _meaningfulLines(text).take(2).toList();
    if (lines.isEmpty) return 'It has no text.';
    return 'It starts with:\n${lines.join('\n')}\n\n'
        'A Headspace file starts with:\n'
        '${acceptedHeaders.join(' or ')}\n$importLine';
  }

  static bool isHeadspaceRecord(NdefRecord r) {
    final text = RecordCodec.decodeText(r);
    return text != null && isHeadspaceText(text);
  }

  /// Reads a Headspace file, or returns null if [text] is not one.
  static Headspace? parse(String text) {
    if (!isHeadspaceText(text)) return null;
    String? name;
    List<String>? traits;
    var modifier = '';
    for (final line in _meaningfulLines(text)) {
      if (line.startsWith('Headspace:')) {
        name = line.substring('Headspace:'.length).trim();
      } else if (line.startsWith('Traits:')) {
        traits = RegExp(r'\[([^\]]*)\]')
            .allMatches(line)
            .map((m) => m.group(1)!.trim())
            .toList();
      } else if (line.startsWith('Modifier:')) {
        final m = RegExp(r'\(([^)]*)\)').firstMatch(line);
        final value = (m?.group(1) ?? '').trim();
        modifier = value == noModifier ? '' : value;
      }
    }
    if (name == null || traits == null || traits.length != traitCount) return null;
    final comments = [
      for (final line in text.split('\n').map((l) => l.trim()))
        if (line.startsWith('//')) line.substring(2),
    ].join('\n');
    return Headspace(
        name: name, traits: traits, modifier: modifier, comments: comments);
  }

  /// The Headspace most recently read from or written to any device (the
  /// newest device contents whose first file is a Headspace file), or null.
  static Headspace? lastKnown(DeviceRegistry registry) {
    NfcDevice? newest;
    Headspace? found;
    for (final d in registry.devices) {
      final first = firstFile(d.records ?? const []);
      final read = d.contentsRead;
      if (first == null || read == null) continue;
      if (newest != null && !read.isAfter(newest.contentsRead!)) continue;
      final text = RecordCodec.decodeText(first);
      final parsed = text == null ? null : parse(text);
      if (parsed != null) {
        newest = d;
        found = parsed;
      }
    }
    return found;
  }

  static List<String> _meaningfulLines(String text) => text
      .split('\n')
      .map((l) => l.replaceAll('\uFEFF', '').trim())
      .where((l) => l.isNotEmpty && !l.startsWith('//'))
      .toList();

  /// The device's first file, not counting Terminal inputs (which every
  /// write removes anyway), or null if there is none.
  static NdefRecord? firstFile(List<NdefRecord> records) {
    for (final r in records) {
      if (!RecordCodec.isTerminalInput(r)) return r;
    }
    return null;
  }

  /// The files to write to a device holding [existing]: [headspace] replaces
  /// its first file (see [firstFile]). Returns null if that first file is not
  /// a Headspace file, in which case nothing may be written.
  static List<NdefRecord>? replaceOnDevice(
      NdefRecord headspace, List<NdefRecord> existing) {
    final first = firstFile(existing);
    if (first == null || !isHeadspaceRecord(first)) return null;
    final at = existing.indexOf(first);
    return [
      ...existing.take(at),
      headspace,
      ...existing.skip(at + 1),
    ];
  }
}

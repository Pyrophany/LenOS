import 'package:flutter_len_os/fs/file_system_model.dart';
import 'package:flutter_len_os/fs/len_file.dart';
import 'package:flutter_len_os/fs/record_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RecordCodec', () {
    test('text record round-trips and keeps language', () {
      final r = RecordCodec.fromText('a.txt', 'héllo');
      expect(RecordCodec.isTextRecord(r), isTrue);
      expect(RecordCodec.decodeText(r), 'héllo');
      final edited = RecordCodec.withText(r, 'bye');
      expect(RecordCodec.decodeText(edited), 'bye');
      expect(edited.payload.sublist(0, 3), [2, 0x65, 0x6E]); // len 2, "en"
    });

    test('uri record compresses prefix', () {
      final r = RecordCodec.fromText('link.url', 'https://www.example.com/x');
      expect(r.payload.first, 2); // https://www.
      expect(RecordCodec.decodeText(r), 'https://www.example.com/x');
    });

    test('text files are suggested as .len', () {
      expect(RecordCodec.extensionFor(RecordCodec.fromText('a.txt', 'x')), 'len');
      expect(RecordCodec.extensionFor(RecordCodec.fromText('a.len', 'x')), 'len');
      expect(RecordCodec.extensionFor(RecordCodec.fromText('a.xyz', 'x')), 'len'); // text/plain
      expect(RecordCodec.extensionFor(RecordCodec.fromText('a.url', 'https://x.y')), 'url');
    });

    test('other extensions become media records', () {
      final r = RecordCodec.fromText('cfg.json', '{"a":1}');
      expect(RecordCodec.mimeType(r), 'application/json');
      expect(RecordCodec.decodeText(r), '{"a":1}');
      expect(RecordCodec.extensionFor(r), 'json');
      expect(RecordCodec.mimeType(RecordCodec.fromText('main.lenos', 'x')),
          'text/plain');
    });
  });

  group('FileSystemModel', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('create, move folder, delete, and reload from storage', () async {
      final fs = FileSystemModel();
      await fs.load();
      fs.createFolder('/notes');
      fs.createFile('/notes/a.txt', RecordCodec.fromText('a.txt', 'A'));
      expect(() => fs.createFile('/notes/a.txt', RecordCodec.fromText('a.txt', 'B')),
          throwsA(isA<FileSystemException>()));
      expect(fs.subfoldersOf('/'), ['/notes']);

      fs.moveFolder('/notes', '/docs');
      expect(fs.fileAt('/docs/a.txt'), isNotNull);
      expect(fs.folderExists('/notes'), isFalse);
      expect(() => fs.moveFolder('/docs', '/docs/inner'),
          throwsA(isA<FileSystemException>()));

      await Future<void>.delayed(Duration.zero); // let the save finish
      final reloaded = FileSystemModel();
      await reloaded.load();
      final LenFile file = reloaded.fileAt('/docs/a.txt')!;
      expect(RecordCodec.decodeText(file.record), 'A');

      reloaded.deleteFolder('/docs');
      expect(reloaded.files, isEmpty);
    });
  });
}

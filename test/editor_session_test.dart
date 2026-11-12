import 'package:flutter_len_os/fs/editor_session.dart';
import 'package:flutter_len_os/fs/file_system_model.dart';
import 'package:flutter_len_os/fs/record_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('multiple tabs: open, dedupe, save, close', () async {
    final fs = FileSystemModel();
    await fs.load();
    final a = fs.createFile('/a.txt', RecordCodec.fromText('a.txt', 'A'));
    final b = fs.createFile('/b.json', RecordCodec.fromText('b.json', '{}'));
    final session = EditorSession(fs);

    session.openFile(a.id);
    session.openFile(b.id);
    session.newFile(folder: '/');
    expect(session.buffers.length, 3);
    expect(session.activeIndex, 2);

    session.openFile(a.id); // Already open: just switches to it.
    expect(session.buffers.length, 3);
    expect(session.activeIndex, 0);

    final tabA = session.active!;
    tabA.controller.text = 'A2';
    expect(tabA.dirty, isTrue);
    session.save(tabA);
    expect(tabA.dirty, isFalse);
    expect(RecordCodec.decodeText(fs.byId(a.id)!.record), 'A2');

    final untitled = session.buffers[2];
    untitled.controller.text = 'new';
    session.saveAs(untitled, 'c.md');
    expect(RecordCodec.mimeType(fs.fileAt('/c.md')!.record), 'text/markdown');

    session.close(tabA);
    expect(session.buffers.length, 2);
    expect(session.activeIndex, 0); // Stays on the first remaining tab.
  });

}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:provider/provider.dart';

import 'device_registry.dart';
import 'ascii_cat.dart';
import 'cat_personality.dart';
import 'docs_page.dart';
import 'fs/editor_session.dart';
import 'fs/file_system_model.dart';
import 'home_sections.dart';
import 'nfc_model.dart';
import 'settings_page.dart';
import 'tab_hooks.dart';
import 'tag_io.dart';
import 'terminal_settings.dart';
import 'theme_model.dart';
import 'user.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NfcModel()),
        // Placeholder until the real [USER] class is added (see user.dart).
        ChangeNotifierProvider(create: (_) => LenOSUser()..load()),
        ChangeNotifierProvider(create: (_) => ThemeModel()..load()),
        ChangeNotifierProvider(create: (_) => TerminalSettings()..load()),
        ChangeNotifierProvider(create: (_) => CatPersonality()..load()),
        // One Lena Kitty for every page she appears on.
        Provider(create: (_) => LenaKitty()),
        ChangeNotifierProvider(create: (_) => DeviceRegistry()..load()),
        ChangeNotifierProvider(create: (_) => FileSystemModel()..load()),
        ChangeNotifierProvider(
          create: (context) => EditorSession(context.read<FileSystemModel>()),
        ),
      ],
      child: const LenOS(),
    ),
  );
}

/// The Home page's greeting, with the first letter of [userName] capitalized.
/// Only the greeting changes; the name itself (e.g. in the Terminal prompt)
/// stays as typed.
String welcomeTitle(String userName) {
  final name = userName.isEmpty
      ? userName
      : userName[0].toUpperCase() + userName.substring(1);
  return 'Welcome, $name';
}

/// Shows snack bars from outside any page, e.g. from the NFC session.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

class LenOS extends StatelessWidget {
  const LenOS({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LenOS',
      theme: ThemeModel.light(
        context.watch<ThemeModel>().accentFor(Brightness.light),
        context.watch<ThemeModel>().topBarColor,
      ),
      darkTheme: ThemeModel.darkTheme(
        context.watch<ThemeModel>().accentFor(Brightness.dark),
        context.watch<ThemeModel>().topBarColor,
      ),
      themeMode: context.watch<ThemeModel>().mode,
      scaffoldMessengerKey: appMessengerKey,
      home: const LenOSShell(),
    );
  }
}

/// Hosts the bottom navigation bar. Each tab has its own [Navigator] (its own
/// widget tree and route stack), and all tabs stay mounted in an [IndexedStack]
/// so their state (scroll position, pushed pages, NFC session) survives
/// switching tabs. App-wide data lives in providers above this widget.
class LenOSShell extends StatefulWidget {
  const LenOSShell({super.key});

  @override
  State<LenOSShell> createState() => _LenOSShellState();
}

class _LenOSShellState extends State<LenOSShell> {
  static const _tabs = <({IconData icon, String label, Widget root})>[
    (icon: Icons.settings, label: 'Settings', root: SettingsPage()),
    (icon: Icons.home, label: 'Home', root: LenOSHome()),
    (icon: Icons.book, label: 'Docs', root: DocsPage()),
  ];

  /// The app opens on Home.
  static const _homeIndex = 1;

  final _navigatorKeys = List.generate(
    _tabs.length,
    (_) => GlobalKey<NavigatorState>(),
  );
  final _tabHooks = List.generate(_tabs.length, (_) => TabHooks());
  int _currentIndex = _homeIndex;

  @override
  void initState() {
    super.initState();
    for (final hooks in _tabHooks) {
      hooks.addListener(_onHooksChanged);
    }
  }

  @override
  void dispose() {
    for (final hooks in _tabHooks) {
      hooks.dispose();
    }
    super.dispose();
  }

  void _onHooksChanged() => setState(() {});

  void _onTabTapped(int index) {
    if (index == _currentIndex) {
      // Tapping the active tab again returns it to its root page,
      // and lets the content reset itself (e.g. Docs goes to the docs home).
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      _tabHooks[index].reselect();
    } else {
      setState(() => _currentIndex = index);
    }
  }

  void _handleBack() {
    final navigator = _navigatorKeys[_currentIndex].currentState;
    // Pages pushed on top of the tab go first, then the tab content (web view history).
    if (navigator?.canPop() ?? false) {
      navigator!.maybePop();
    } else {
      _tabHooks[_currentIndex].goBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentNavigator = _navigatorKeys[_currentIndex].currentState;
    final tabHandlesBack =
        (currentNavigator?.canPop() ?? false) ||
        _tabHooks[_currentIndex].canGoBack;
    return PopScope(
      // Let the system back button close the app only when the active tab has nothing to go back to.
      canPop: !tabHandlesBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              // Animations in hidden tabs (e.g. the Home cat) pause.
              TickerMode(
                enabled: i == _currentIndex,
                child: ChangeNotifierProvider<TabHooks>.value(
                  value: _tabHooks[i],
                  child: Navigator(
                    key: _navigatorKeys[i],
                    // Rebuild the shell when a tab pushes or pops so canPop stays accurate.
                    observers: [_TabNavigatorObserver(() => setState(() {}))],
                    onGenerateRoute: (settings) => MaterialPageRoute(
                      settings: settings,
                      builder: (_) => _tabs[i].root,
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          items: [
            for (final tab in _tabs)
              BottomNavigationBarItem(icon: Icon(tab.icon), label: tab.label),
          ],
        ),
      ),
    );
  }
}

class _TabNavigatorObserver extends NavigatorObserver {
  _TabNavigatorObserver(this.onChanged);

  final VoidCallback onChanged;

  void _notify() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _notify();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _notify();
}

class LenOSHome extends StatefulWidget {
  const LenOSHome({super.key});

  @override
  State<LenOSHome> createState() => _LenOSHomeState();
}

class _LenOSHomeState extends State<LenOSHome> with WidgetsBindingObserver {
  bool _sessionActive = false;
  late final NfcModel _nfc;
  late final DeviceRegistry _devices;
  late final TagIo _tagIo;

  @override
  void initState() {
    super.initState();
    _nfc = context.read<NfcModel>();
    _devices = context.read<DeviceRegistry>();
    _tagIo = TagIo(_nfc, _devices);
    WidgetsBinding.instance.addObserver(this);
    _startSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSession();
    super.dispose();
  }

  // Android drops reader mode when the app is backgrounded, so restart the
  // session whenever we come back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSession();
    } else if (state == AppLifecycleState.paused) {
      _stopSession();
    }
  }

  Future<void> _startSession() async {
    if (_sessionActive) return;
    final availability = await NfcManager.instance.checkAvailability();
    if (!mounted || availability != NfcAvailability.enabled) return;

    _sessionActive = true;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
        }, // You can also specify iso18092 and iso15693.
        // Keep the iOS session alive after a read instead of closing it.
        invalidateAfterFirstReadIos: false,
        onDiscovered: _onTagDiscovered,
      );
      _nfc.setReaderActive(true);
    } catch (e) {
      _sessionActive = false;
      debugPrint('Failed to start NFC session: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _stopSession() async {
    if (!_sessionActive) return;
    _sessionActive = false;
    // Deferred: this also runs from dispose(), where notifying listeners is not allowed.
    Future.microtask(() => _nfc.setReaderActive(false));
    try {
      await NfcManager.instance.stopSession();
    } catch (e) {
      debugPrint('Failed to stop NFC session: $e');
    }
    if (mounted) setState(() {});
  }

  /// True while a tag is being read or written. Tags re-detected meanwhile
  /// (common when a tag is held at the edge of range) are ignored, so a read
  /// never runs in the middle of a write.
  bool _tagBusy = false;

  Future<void> _onTagDiscovered(NfcTag tag) async {
    if (_tagBusy) return;
    _tagBusy = true;
    try {
      await _handleTag(tag);
    } finally {
      _tagBusy = false;
    }
  }

  Future<void> _handleTag(NfcTag tag) async {
    final uid = _tagUid(tag);
    if (uid == null) {
      debugPrint('Could not determine the tag UID.');
      return;
    }
    _devices.recordScan(uid);
    final ndef = Ndef.from(tag);
    // Queued work (e.g. from the Terminal) takes this tag instead of a plain
    // read. A hold keeps the tag (and re-detections are ignored) until done.
    final pendingHold = _nfc.takePendingHold();
    if (pendingHold != null) return _tagIo.hold(uid, ndef, pendingHold);
    final pendingWrite = _nfc.takePendingWrite();
    if (pendingWrite != null) return _tagIo.write(uid, ndef, pendingWrite);
    if (ndef == null) {
      debugPrint('Tag $uid is not compatible with NDEF.');
      return;
    }
    final ok = await _tagIo.read(uid, ndef);
    if (!ok) await _logTagDiagnostics(uid, tag, ndef);
  }

  /// Read-only: prints what Android reports about a tag whose files could
  /// not be read, and its first 64 bytes of memory (UID, lock bytes, the
  /// capability container and the start of the NDEF data), to find out why.
  Future<void> _logTagDiagnostics(String uid, NfcTag tag, Ndef ndef) async {
    debugPrint('Diagnostics for $uid: ndef maxSize=${ndef.maxSize} '
        'writable=${ndef.isWritable} cached=${ndef.cachedMessage != null} '
        'info=${ndef.additionalData}');
    final ul = MifareUltralightAndroid.from(tag);
    if (ul == null) {
      debugPrint('Diagnostics for $uid: no raw (MIFARE Ultralight) access.');
      return;
    }
    String hex(Iterable<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    for (var page = 0; page < 16; page += 4) {
      try {
        final data = await ul.readPages(pageOffset: page);
        for (var i = 0; i + 4 <= data.length; i += 4) {
          debugPrint('  page ${(page + i ~/ 4).toString().padLeft(2)}: '
              '${hex(data.sublist(i, i + 4))}');
        }
      } catch (e) {
        debugPrint('  pages $page-${page + 3}: read failed: $e');
        return;
      }
    }
  }

  /// Returns the tag UID as hex, using whichever platform tag type is present.
  String? _tagUid(NfcTag tag) {
    final Uint8List? id =
        NfcTagAndroid.from(tag)?.id ??
        MiFareIos.from(tag)?.identifier ??
        Iso7816Ios.from(tag)?.identifier ??
        Iso15693Ios.from(tag)?.identifier ??
        FeliCaIos.from(tag)?.currentIDm;
    return id == null ? null : NfcModel.uidToHex(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // A taller bar for the larger greeting.
        toolbarHeight: 72,
        title: Text(
          welcomeTitle(context.watch<LenOSUser>().name),
          style: Theme.of(context).appBarTheme.titleTextStyle
              ?.copyWith(fontSize: 28, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: const HomeSectionList(
        sections: [
          HeadspaceManagerSection(),
          DevicesSection(),
          LenOSCodeSection(),
          TerminalSection(),
          CodebaseSection(),
        ],
        // The cat lives in the space under the cards.
        footer: AsciiCat(),
        footerHeight: AsciiCat.defaultHeight,
      ),
    );
  }
}

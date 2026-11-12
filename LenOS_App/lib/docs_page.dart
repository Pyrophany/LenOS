import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'tab_hooks.dart';

/// Browses the LenOS documentation on Read the Docs.
///
/// Only pages on [docsHost] open inside the tab; every other link is handed to
/// the system browser. The tab keeps its own browsing history (see
/// [_DocsHistory]) so back/forward and the last page viewed survive restarts.
class DocsPage extends StatefulWidget {
  const DocsPage({super.key});

  static final Uri homeUrl = Uri.parse('https://lenos.readthedocs.io/en/latest/');
  static final String docsHost = homeUrl.host;

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  late final WebViewController _controller;
  late final TabHooks _hooks;
  final _history = _DocsHistory();

  int _progress = 0;
  String? _error;

  /// History index of a back/forward/restore load in flight. The next URL
  /// change lands on that entry instead of being recorded as a new page.
  int? _pendingIndex;

  @override
  void initState() {
    super.initState();
    _hooks = context.read<TabHooks>();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _onUrlChanged(url);
          },
          onPageFinished: (_) => _pendingIndex = null,
          onWebResourceError: (error) {
            // Ignore failures of images, scripts, ads etc.; only a failed page load matters.
            if (error.isForMainFrame ?? true) {
              _pendingIndex = null;
              if (mounted) setState(() => _error = error.description);
            }
          },
        ),
      );
    _restore();
  }

  @override
  void dispose() {
    _hooks.reset();
    super.dispose();
  }

  /// Reopens the page the user was last on, or the docs home on first run.
  Future<void> _restore() async {
    await _history.load();
    if (!mounted) return;
    final current = _history.current;
    if (current == null) {
      _controller.loadRequest(DocsPage.homeUrl);
    } else {
      _loadHistoryEntry(_history.index);
    }
    _syncNavState();
  }

  Future<NavigationDecision> _onNavigationRequest(
    NavigationRequest request,
  ) async {
    // Let embedded frames (search widgets, etc.) load normally.
    if (!request.isMainFrame) return NavigationDecision.navigate;

    final uri = Uri.tryParse(request.url);
    if (uri == null || uri.host == DocsPage.docsHost) {
      return NavigationDecision.navigate;
    }
    // Everything off the docs site opens outside the app.
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not open ${request.url}');
    }
    return NavigationDecision.prevent;
  }

  void _onUrlChanged(String url) {
    // Skip about:blank and the like; only docs pages belong in the history.
    if (Uri.tryParse(url)?.host != DocsPage.docsHost) return;
    final pending = _pendingIndex;
    if (pending != null) {
      _pendingIndex = null;
      // Keep the URL the page actually ended up on (e.g. after a redirect).
      _history.moveTo(pending, url);
    } else {
      _history.visit(url);
    }
    _syncNavState();
  }

  void _loadHistoryEntry(int index) {
    final uri = Uri.tryParse(_history.entries[index]);
    if (uri == null) return;
    _pendingIndex = index;
    _controller.loadRequest(uri);
  }

  Future<void> _goBack() async {
    if (_history.canGoBack) _loadHistoryEntry(_history.index - 1);
  }

  void _goForward() {
    if (_history.canGoForward) _loadHistoryEntry(_history.index + 1);
  }

  /// Refreshes the toolbar buttons and tells the shell whether the system
  /// back button should go back inside the docs.
  void _syncNavState() {
    if (!mounted) return;
    setState(() {});
    _hooks.update(
      canGoBack: _history.canGoBack,
      onBack: _goBack,
      onReselect: _goHome,
    );
  }

  void _goHome() => _controller.loadRequest(DocsPage.homeUrl);

  void _reload() {
    setState(() => _error = null);
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final loading = _progress < 100 && _error == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('LenOS Docs'),
        actions: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: _history.canGoBack ? _goBack : null,
          ),
          IconButton(
            tooltip: 'Forward',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _history.canGoForward ? _goForward : null,
          ),
          IconButton(
            tooltip: 'Docs home',
            icon: const Icon(Icons.home),
            onPressed: _goHome,
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
        bottom: loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: _error == null
          ? WebViewWidget(controller: _controller)
          : _ErrorView(message: _error!, onRetry: _reload),
    );
  }
}

/// The Docs tab's browsing history, saved to disk on every change.
///
/// The web view's own history is lost when the app closes, so the tab keeps
/// this list itself and drives back/forward from it.
class _DocsHistory {
  static const _entriesKey = 'docs.history.entries';
  static const _indexKey = 'docs.history.index';
  static const _maxEntries = 50;

  List<String> entries = [];
  int index = -1;

  String? get current => index >= 0 ? entries[index] : null;
  bool get canGoBack => index > 0;
  bool get canGoForward => index < entries.length - 1;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      entries = [...?prefs.getStringList(_entriesKey)];
      index = (prefs.getInt(_indexKey) ?? entries.length - 1)
          .clamp(-1, entries.length - 1);
    } catch (e) {
      debugPrint('Could not load docs history: $e');
    }
  }

  /// Records a newly opened page, dropping any forward entries.
  void visit(String url) {
    if (url == current) return; // Reload or same-page update.
    entries = [...entries.take(index + 1), url];
    if (entries.length > _maxEntries) {
      entries = entries.sublist(entries.length - _maxEntries);
    }
    index = entries.length - 1;
    _save();
  }

  /// Makes [newIndex] the current entry after a back/forward load.
  void moveTo(int newIndex, String url) {
    if (newIndex < 0 || newIndex >= entries.length) return visit(url);
    index = newIndex;
    entries[newIndex] = url;
    _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_entriesKey, entries);
      await prefs.setInt(_indexKey, index);
    } catch (e) {
      debugPrint('Could not save docs history: $e');
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            const Text("Couldn't load the docs."),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

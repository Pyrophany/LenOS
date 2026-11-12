import 'package:flutter/foundation.dart';

/// Lets a tab's content take part in shell-level navigation: the system back
/// button and re-tapping the active tab. One instance exists per tab, provided
/// above that tab's [Navigator].
class TabHooks extends ChangeNotifier {
  bool _canGoBack = false;
  Future<void> Function()? _onBack;
  VoidCallback? _onReselect;
  bool _disposed = false;

  /// Whether the tab content wants to handle the next back press itself.
  bool get canGoBack => _canGoBack && _onBack != null;

  /// Registers the content's handlers. Call again whenever [canGoBack] changes.
  void update({
    required bool canGoBack,
    Future<void> Function()? onBack,
    VoidCallback? onReselect,
  }) {
    if (_disposed) return;
    _onBack = onBack;
    _onReselect = onReselect;
    if (_canGoBack != canGoBack) {
      _canGoBack = canGoBack;
      notifyListeners();
    }
  }

  /// Clears all handlers, e.g. when the registering widget is disposed.
  void reset() => update(canGoBack: false);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> goBack() async {
    if (canGoBack) await _onBack!();
  }

  /// Called when the user taps the tab that is already selected.
  void reselect() => _onReselect?.call();
}

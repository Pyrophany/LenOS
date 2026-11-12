import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ascii_cat.dart';
import 'device_registry.dart';
import 'headspace.dart';
import 'headspace_catalog.dart';
import 'headspace_favorites.dart';
import 'nfc_model.dart';
import 'nfc_writing_dialog.dart';
import 'terminal_style.dart';

/// Builds a Headspace file and writes it over the Headspace file that is the
/// first file on the INTERFACE device. The form is laid out like the file.
class HeadspaceManagerPage extends StatefulWidget {
  const HeadspaceManagerPage({super.key});

  @override
  State<HeadspaceManagerPage> createState() => _HeadspaceManagerPageState();
}

/// Dropdown value meaning "type your own".
const _custom = '\u0000custom';

class _Choice {
  String? value;
  final custom = TextEditingController();

  /// Focus for the Custom input, moved there explicitly when Custom is
  /// chosen (autofocus does nothing while another field has focus).
  final focus = FocusNode();

  String get text => value == _custom ? custom.text.trim() : (value ?? '');
}

class _HeadspaceManagerPageState extends State<HeadspaceManagerPage> {
  HeadspaceCatalog _catalog = HeadspaceCatalog.defaults;
  final _headspace = _Choice();
  final _traits = List.generate(Headspace.traitCount, (_) => _Choice());
  final _modifier = TextEditingController();

  /// Set when a favorite without a Modifier fills the form: the blank
  /// Modifier then means (none) instead of the last known Modifier.
  /// Cleared as soon as the Modifier is typed in.
  bool _blankIsNone = false;

  /// Comments stay the same whatever Headspace is chosen, and are saved
  /// between visits.
  final _comments = TextEditingController();
  static const _commentsKey = 'lenos.headspace.comments';

  /// Shown above the Write button after a problem.
  String? _error;

  /// Null until loaded.
  HeadspaceFavorites? _favorites;

  @override
  void initState() {
    super.initState();
    HeadspaceCatalog.load().then((catalog) {
      if (mounted) setState(() => _catalog = catalog);
    });
    _loadComments();
    HeadspaceFavorites.load().then((f) {
      if (mounted) setState(() => _favorites = f);
    });
  }

  Future<void> _loadComments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_commentsKey);
      // Don't replace anything typed while loading.
      if (saved != null && mounted && _comments.text.isEmpty) {
        _comments.text = saved;
      }
    } catch (e) {
      debugPrint('Could not load Headspace comments: $e');
    }
  }

  Future<void> _saveComments(String text) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_commentsKey, text);
    } catch (e) {
      debugPrint('Could not save Headspace comments: $e');
    }
  }

  @override
  void dispose() {
    for (final c in [_headspace, ..._traits]) {
      c.custom.dispose();
      c.focus.dispose();
    }
    _modifier.dispose();
    _comments.dispose();
    super.dispose();
  }

  /// The Headspace from the form, or null after showing what is missing.
  ///
  /// Empty fields (untouched, or Custom left blank) use the last known
  /// Headspace's values, which are shown as their placeholders.
  Headspace? _build() {
    final (headspace, problem) = _resolve();
    if (problem != null) {
      setState(() => _error = problem);
      return null;
    }
    return headspace;
  }

  /// The Headspace from the form, or why there is none. No side effects.
  (Headspace?, String?) _resolve() {
    final known = Headspace.lastKnown(context.read<DeviceRegistry>());
    String valueOf(_Choice c, String? fallback) =>
        c.text.isNotEmpty ? c.text : (fallback ?? '');

    final name = valueOf(_headspace, known?.name);
    final traits = [
      for (var i = 0; i < _traits.length; i++)
        valueOf(_traits[i], known?.traits[i]),
    ];
    final modifier = _modifier.text.trim().isNotEmpty
        ? _modifier.text
        : (_blankIsNone ? '' : (known?.modifier ?? ''));

    String? problem;
    if (name.isEmpty && _headspace.value == null) {
      problem = 'Choose a Headspace.';
    } else {
      problem = Headspace.validatePart(name, what: 'Headspace');
    }
    for (var i = 0; problem == null && i < traits.length; i++) {
      problem = traits[i].isEmpty && _traits[i].value == null
          ? 'Choose Trait ${i + 1}.'
          : Headspace.validatePart(traits[i], what: 'Trait ${i + 1}');
    }
    problem ??= Headspace.validateModifier(modifier);
    if (problem != null) return (null, problem);
    return (
      Headspace(
        name: name,
        traits: traits,
        modifier: modifier,
        comments: _comments.text,
      ),
      null,
    );
  }

  /// Adds the Headspace in the form to the favorites, or removes it if it
  /// is one already.
  Future<void> _toggleFavorite() async {
    final favorites = _favorites;
    if (favorites == null) return;
    final headspace = _build();
    if (headspace == null) return;
    setState(() => _error = null);
    final added = await favorites.toggle(headspace);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            added
                ? '"${headspace.name.trim()}" added to favorites.'
                : '"${headspace.name.trim()}" removed from favorites.',
          ),
        ),
      );
  }

  /// Fills the form with [favorite]. Comments are left as they are.
  void _applyFavorite(Headspace favorite) {
    void fill(_Choice c, String value, List<String> options) {
      if (options.contains(value)) {
        c.value = value;
      } else {
        c.value = _custom;
        c.custom.text = value;
      }
    }

    setState(() {
      fill(_headspace, favorite.name, _catalog.headspaces);
      for (var i = 0; i < _traits.length; i++) {
        fill(_traits[i], favorite.traits[i], _catalog.traits);
      }
      // Blank stays (none) rather than using the last known Modifier.
      _modifier.text = favorite.modifier;
      _blankIsNone = favorite.modifier.isEmpty;
      _error = null;
    });
  }

  Future<void> _write() async {
    final headspace = _build();
    if (headspace == null) return;
    setState(() => _error = null);
    final record = headspace.toRecord();
    final nfc = context.read<NfcModel>();

    final write = nfc.writeToNextTag(
      build: (existing) {
        final files = Headspace.replaceOnDevice(record, existing);
        if (files == null) {
          final first = Headspace.firstFile(existing);
          throw NfcWriteException(
            first == null
                ? 'This device has no files, so there is no Headspace file to '
                      'replace. Nothing was written.'
                : 'The first file on this device is not a Headspace file. '
                      'Nothing was written.\n\n'
                      '${Headspace.mismatchReason(first)}',
          );
        }
        return files;
      },
    );
    String? uid;
    write.then<void>((u) => uid = u, onError: (Object _) {});

    final outcome = await showNfcWritingDialog(
      context,
      label: 'the INTERFACE device',
      message:
          'Hold the INTERFACE device near the phone to write the Headspace.',
      write: write,
      onCancel: nfc.cancelWrite,
    );
    if (!mounted) return;
    if (outcome == true) {
      final label =
          context.read<DeviceRegistry>().byUid(uid ?? '')?.label ?? uid;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Headspace "${headspace.name}" written to $label.'),
          ),
        );
    } else if (outcome != null) {
      setState(() => _error = 'Write failed: $outcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    const code = TerminalStyle.font;
    final keyword = code.copyWith(color: ts.accent);
    // The last known inputs are shown as placeholders.
    final known = Headspace.lastKnown(context.watch<DeviceRegistry>());
    final plain = code.copyWith(color: ts.text);
    final punctuation = code.copyWith(color: ts.dim);
    final current = _resolve().$1;
    final isFavorite =
        current != null && (_favorites?.contains(current) ?? false);

    return Scaffold(
      backgroundColor: ts.background,
      appBar: AppBar(
        title: const Text('Headspace Manager'),
        actions: [
          PopupMenuButton<Headspace>(
            tooltip: 'Favorites',
            icon: const Icon(Icons.menu),
            enabled: _favorites != null,
            onSelected: _applyFavorite,
            itemBuilder: (_) {
              final items = _favorites?.items ?? const <Headspace>[];
              if (items.isEmpty) {
                return const [
                  PopupMenuItem<Headspace>(
                    enabled: false,
                    child: Text('No favorites yet. Tap the star to add one.'),
                  ),
                ];
              }
              return [
                for (final f in items)
                  PopupMenuItem<Headspace>(
                    value: f,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.star),
                      title: Text(f.name),
                      subtitle: Text(
                        [
                          f.traits.map((t) => '[$t]').join(','),
                          '(${f.modifier.isEmpty ? Headspace.noModifier : f.modifier})',
                        ].join(' '),
                      ),
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
      body: CatBackdrop(
        child: Theme(
          data: Theme.of(context),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ts.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ts.faint),
                  ),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Headspace.header, style: keyword),
                          Text(Headspace.importLine, style: keyword),
                          const SizedBox(height: 4),
                          _Line(
                            label: Text('Headspace:', style: plain),
                            child: _ChoiceField(
                              choice: _headspace,
                              options: _catalog.headspaces,
                              hint: 'Headspace',
                              placeholder: known?.name,
                              onChanged: () => setState(() => _error = null),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Traits:', style: plain),
                          for (var i = 0; i < _traits.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: _Line(
                                label: Text('[', style: punctuation),
                                // Same width as the Modifier's ")", so the
                                // inputs end at the same place.
                                trailing: Text(']', style: punctuation),
                                child: _ChoiceField(
                                  choice: _traits[i],
                                  options: _catalog.traits,
                                  hint: 'Trait ${i + 1}',
                                  placeholder: known?.traits[i],
                                  onChanged: () =>
                                      setState(() => _error = null),
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          _Line(
                            label: Text('Modifier:(', style: plain),
                            trailing: Text(')', style: plain),
                            child: TextField(
                              controller: _modifier,
                              style: plain,
                              autocorrect: false,
                              onChanged: (_) => setState(() {
                                _error = null;
                                _blankIsNone = false;
                              }),
                              decoration: InputDecoration(
                                isDense: true,
                                // Blank unless a Modifier is known.
                                hintText: _blankIsNone ? null : known?.modifier,
                                hintStyle: code.copyWith(color: ts.faint),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: ts.faint),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: ts.accent),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: IconButton(
                          tooltip: isFavorite
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: ts.accent,
                          ),
                          onPressed: _favorites == null
                              ? null
                              : _toggleFavorite,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ts.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ts.faint),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Comments', style: plain),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _comments,
                        minLines: 3,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: code.copyWith(color: ts.dim),
                        onChanged: _saveComments,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'One comment per line',
                          hintStyle: code.copyWith(color: ts.faint),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: ts.faint),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: ts.accent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Added after the Headspace, each line starting with //. '
                        'Kept when the Headspace changes.',
                        style: code.copyWith(fontSize: 12, color: ts.dim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    'Options will come from the LenOS docs once they are written.',
                    if (known != null)
                      'Empty fields use the last known values shown in grey.',
                    known != null && known.modifier.isNotEmpty
                        ? 'Type none for no Modifier.'
                        : 'Leave Modifier blank for (none).',
                  ].join(' '),
                  style: code.copyWith(fontSize: 12, color: ts.dim),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error, color: ts.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: code.copyWith(color: ts.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: ts.accent,
                      foregroundColor: Colors.black,
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    onPressed: _write,
                    icon: const Icon(Icons.nfc, size: 28),
                    label: const Text('WRITE'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of the file: a fixed label, an input, and optional closing text.
class _Line extends StatelessWidget {
  const _Line({required this.label, required this.child, this.trailing});

  final Widget label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      label,
      const SizedBox(width: 4),
      Expanded(child: child),
      if (trailing != null) ...[const SizedBox(width: 4), trailing!],
    ],
  );
}

/// A dropdown of [options] with Custom at the top. Choosing Custom replaces
/// the dropdown with a text input in green, the color of custom values.
class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.choice,
    required this.options,
    required this.hint,
    required this.onChanged,
    this.placeholder,
  });

  final _Choice choice;
  final List<String> options;

  /// What the field is, e.g. `Trait 1`; the placeholder if none is known.
  final String hint;

  /// The last known value, shown as the placeholder when set.
  final String? placeholder;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    const code = TerminalStyle.font;
    if (choice.value == _custom) {
      return TextField(
        controller: choice.custom,
        focusNode: choice.focus,
        autocorrect: false,
        enableSuggestions: false,
        style: code.copyWith(color: ts.accent),
        cursorColor: ts.accent,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          isDense: true,
          hintText: placeholder ?? 'Custom ${hint.toLowerCase()}',
          hintStyle: code.copyWith(color: ts.faint),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: ts.faint),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: ts.accent),
          ),
          // Back to the list, once there are options to choose from.
          suffixIcon: options.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Choose from list',
                  icon: Icon(Icons.arrow_drop_down, color: ts.accent),
                  onPressed: () {
                    choice.value = null;
                    onChanged();
                  },
                ),
          suffixIconConstraints: const BoxConstraints(
            minHeight: 24,
            minWidth: 32,
          ),
        ),
      );
    }

    return DropdownButton<String>(
      value: options.contains(choice.value) ? choice.value : null,
      isExpanded: true,
      isDense: true,
      hint: Text(placeholder ?? hint, style: code.copyWith(color: ts.faint)),
      dropdownColor: ts.raised,
      iconEnabledColor: ts.accent,
      style: code.copyWith(color: ts.text),
      underline: Container(height: 1, color: ts.faint),
      items: [
        DropdownMenuItem(
          value: _custom,
          child: Text('Custom…', style: code.copyWith(color: ts.accent)),
        ),
        for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: (v) {
        choice.value = v;
        onChanged();
        if (v == _custom) {
          // After the menu closes and the input is built, so focus lands
          // here rather than going back to the previously focused field.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => choice.focus.requestFocus(),
          );
        }
      },
    );
  }
}

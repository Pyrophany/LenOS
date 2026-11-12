import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ascii_cat.dart';
import 'color_picker_dialog.dart';
import 'device_registry.dart';
import 'lena_kitty_page.dart';
import 'fs/fs_dialogs.dart';
import 'terminal_settings.dart';
import 'terminal_style.dart';
import 'theme_model.dart';
import 'user.dart';

/// Settings, opened from the Home page.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeModel>();
    final terminal = context.watch<TerminalSettings>();
    final deviceCount = context.watch<DeviceRegistry>().devices.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: CatBackdrop(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const _UserNameField(),
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: const Text('Dark mode'),
              value: theme.dark,
              onChanged: (value) => theme.dark = value,
            ),
            _AccentPicker(theme: theme),
            _TopBarPicker(theme: theme),
            SwitchListTile(
              secondary: const Icon(Icons.speed),
              title: const Text('Dynamic intervals'),
              subtitle: const Text(
                'fractionate speeds up: 2 s, then 1.5 s after 6 trances, '
                '1 s after 10',
              ),
              value: terminal.dynamicIntervals,
              onChanged: (value) => terminal.dynamicIntervals = value,
            ),
            ListTile(
              leading: const Icon(Icons.pets),
              title: const Text('Lena Kitty'),
              subtitle: const Text(':3'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LenaKittyPage())),
            ),
            ListTile(
              leading: const Icon(Icons.nfc),
              title: const Text('Scanned devices'),
              subtitle: Text(
                deviceCount == 1 ? '1 device' : '$deviceCount devices',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DevicesPage())),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled row of color swatches ending in a Custom swatch that opens the
/// color picker. The chosen swatch has a check mark.
class _SwatchPicker extends StatelessWidget {
  const _SwatchPicker({
    required this.title,
    required this.icon,
    required this.semanticsSuffix,
    required this.swatches,
    required this.custom,
    required this.customChosen,
    required this.onCustom,
  });

  final String title;
  final IconData icon;

  /// Added to each swatch's label for screen readers, e.g. `accent`.
  final String semanticsSuffix;
  final List<({String label, Color color, bool chosen, VoidCallback onTap})>
  swatches;

  /// The custom color, or null before one has been chosen.
  final Color? custom;
  final bool customChosen;
  final Future<void> Function() onCustom;

  static Color _onColor(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark
      ? Colors.white
      : Colors.black;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    final chosen = swatches.where((s) => s.chosen).firstOrNull;
    final valueLabel = customChosen && custom != null
        ? colorToHex(custom!)
        : chosen?.label ?? '';

    Widget swatch({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      required BoxDecoration decoration,
      required Widget? child,
    }) => Semantics(
      button: true,
      selected: selected,
      label: '$label $semanticsSuffix',
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          child: Container(
            width: 44,
            height: 44,
            decoration: decoration.copyWith(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? ts.text : ts.faint,
                width: selected ? 3 : 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ts.accent),
              const SizedBox(width: 16),
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
              const Spacer(),
              Text(valueLabel, style: TextStyle(color: ts.dim)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final s in swatches)
                swatch(
                  label: s.label,
                  selected: s.chosen,
                  onTap: s.onTap,
                  decoration: BoxDecoration(color: s.color),
                  child: s.chosen
                      ? Icon(Icons.check, color: _onColor(s.color))
                      : null,
                ),
              swatch(
                label: 'Custom',
                selected: customChosen,
                onTap: onCustom,
                decoration: BoxDecoration(
                  color: custom,
                  gradient: custom == null
                      ? const SweepGradient(
                          colors: [
                            Colors.red,
                            Colors.yellow,
                            Colors.green,
                            Colors.cyan,
                            Colors.blue, Colors.purple, Colors.red, //
                          ],
                        )
                      : null,
                ),
                child: Icon(
                  customChosen ? Icons.check : Icons.edit,
                  size: customChosen ? 24 : 18,
                  color: custom == null ? Colors.white : _onColor(custom!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Accent color: presets (in the shade for the current mode) or Custom.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.theme});

  final ThemeModel theme;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return _SwatchPicker(
      title: 'Accent color',
      icon: Icons.palette,
      semanticsSuffix: 'accent',
      swatches: [
        for (final a in AccentColor.values)
          (
            label: a.label,
            color: a.forBrightness(brightness),
            chosen: !theme.usingCustom && a == theme.accent,
            onTap: () => theme.accent = a,
          ),
      ],
      custom: theme.customAccent,
      customChosen: theme.usingCustom,
      onCustom: () async {
        final picked = await showColorPickerDialog(
          context,
          initial: theme.customAccent ?? TerminalStyle.of(context).accent,
        );
        if (picked != null) theme.useCustomAccent(picked);
      },
    );
  }
}

/// Top bar color: presets or Custom.
class _TopBarPicker extends StatelessWidget {
  const _TopBarPicker({required this.theme});

  final ThemeModel theme;

  @override
  Widget build(BuildContext context) {
    return _SwatchPicker(
      title: 'Top bar color',
      icon: Icons.web_asset,
      semanticsSuffix: 'top bar',
      swatches: [
        for (final p in ThemeModel.topBarPresets)
          (
            label: p.label,
            color: p.color,
            chosen: !theme.topBarIsCustom && p.color == theme.topBarColor,
            onTap: () => theme.topBarColor = p.color,
          ),
      ],
      custom: theme.customTopBar,
      customChosen: theme.topBarIsCustom,
      onCustom: () async {
        final picked = await showColorPickerDialog(
          context,
          title: 'Custom top bar color',
          initial: theme.customTopBar ?? theme.topBarColor,
          // Titles on the bar switch between black and white to stay readable.
          checkReadability: false,
        );
        if (picked != null) theme.useCustomTopBar(picked);
      },
    );
  }
}

/// Edits the [USER] name. Valid input is applied as you type.
class _UserNameField extends StatefulWidget {
  const _UserNameField();

  @override
  State<_UserNameField> createState() => _UserNameFieldState();
}

class _UserNameFieldState extends State<_UserNameField> {
  late final LenOSUser _user = context.read<LenOSUser>();
  late final _controller = TextEditingController(text: _user.name);

  /// The name as this field last showed or set it.
  late String _shown;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shown = _user.name;
    // Settings is a tab, so this field exists from startup, usually before
    // the saved name has loaded: show it once it arrives.
    _user.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onUserChanged() {
    if (_user.name == _shown) return; // Our own edit.
    _shown = _user.name;
    _controller.text = _user.name;
    if (mounted) setState(() => _error = null);
  }

  void _onChanged(String value) {
    final error = LenOSUser.validateName(value);
    setState(() => _error = error);
    if (error == null) {
      _shown = value.trim().isEmpty ? LenOSUser.defaultName : value.trim();
      _user.name = value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<LenOSUser>().name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _controller,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: _onChanged,
        decoration: InputDecoration(
          labelText: 'Username',
          prefixIcon: const Icon(Icons.person),
          border: const OutlineInputBorder(),
          errorText: _error,
          helperText: 'Terminal prompt: $name@LenOS:~\$',
        ),
      ),
    );
  }
}

/// Every NFC device ever scanned. Tap to name, star to favorite.
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<DeviceRegistry>();
    final devices = registry.devices;
    final named = devices.where((d) => d.name != null).toList();
    final unnamed = devices.where((d) => d.name == null).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Scanned Devices')),
      body: devices.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No devices scanned yet.\n'
                  'Hold an NFC device near the phone while LenOS is open.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Tap a device to name it. Favorites appear in Devices on the Home page.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (named.isNotEmpty) const _Header('Named'),
                for (final d in named) _DeviceTile(device: d),
                if (unnamed.isNotEmpty && named.isNotEmpty)
                  const _Header('Unnamed'),
                for (final d in unnamed) _DeviceTile(device: d),
              ],
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final NfcDevice device;

  @override
  Widget build(BuildContext context) {
    final registry = context.read<DeviceRegistry>();
    final lastSeen = 'Last seen ${_formatDate(device.lastSeen)}';
    return ListTile(
      leading: const Icon(Icons.nfc),
      title: Text(device.label),
      subtitle: Text(
        device.name == null ? lastSeen : '${device.uid}\n$lastSeen',
      ),
      isThreeLine: device.name != null,
      trailing: IconButton(
        tooltip: device.favorite ? 'Remove from favorites' : 'Add to favorites',
        icon: Icon(
          device.favorite ? Icons.star : Icons.star_border,
          color: device.favorite ? Colors.amber : null,
        ),
        onPressed: () => registry.setFavorite(device.uid, !device.favorite),
      ),
      onTap: () async {
        final name = await promptText(
          context,
          title: 'Name ${device.uid}',
          initial: device.name ?? '',
          confirmLabel: 'Save',
          validator: (n) => n.length > 40 ? 'At most 40 characters' : null,
        );
        // Saving an empty name removes it.
        if (name != null) registry.rename(device.uid, name);
      },
    );
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

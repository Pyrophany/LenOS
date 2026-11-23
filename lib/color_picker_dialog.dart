import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'terminal_style.dart';

/// Asks for a color: by picker (hue, saturation, brightness), by hex, or by
/// red/green/blue values, all kept in sync. Returns null if cancelled.
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  required Color initial,
  String title = 'Custom accent color',
  bool checkReadability = true,
}) =>
    showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(
          initial: initial, title: title, checkReadability: checkReadability),
    );

/// `#RRGGBB` for [color].
String colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Reads `#RRGGBB`, `RRGGBB`, `#RGB` or `RGB` (any case). Null if invalid.
Color? colorFromHex(String text) {
  var hex = text.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

/// WCAG contrast ratio between two colors (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Below this, accent-colored text is hard to read.
const minReadableContrast = 3.0;

int _channel(double c) => (c * 255).round().clamp(0, 255);

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initial,
    required this.title,
    required this.checkReadability,
  });

  final Color initial;
  final String title;

  /// Show the color as text on both backgrounds, warning if hard to read.
  /// Otherwise just a plain swatch.
  final bool checkReadability;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial.withAlpha(0xFF));
  final _hex = TextEditingController();
  final _rgb = List.generate(3, (_) => TextEditingController());
  String? _hexError;

  Color get _color => _hsv.toColor();

  @override
  void initState() {
    super.initState();
    _syncFields();
  }

  @override
  void dispose() {
    _hex.dispose();
    for (final c in _rgb) {
      c.dispose();
    }
    super.dispose();
  }

  /// Writes the current color into the hex and RGB fields, except [skip]
  /// (the field being typed in, so the cursor isn't disturbed).
  void _syncFields({TextEditingController? skip}) {
    final c = _color;
    if (skip != _hex) _hex.text = colorToHex(c);
    final values = [_channel(c.r), _channel(c.g), _channel(c.b)];
    for (var i = 0; i < 3; i++) {
      if (skip != _rgb[i]) _rgb[i].text = '${values[i]}';
    }
  }

  void _setHsv(HSVColor hsv) => setState(() {
        _hsv = hsv;
        _hexError = null;
        _syncFields();
      });

  /// Takes a color typed as hex or RGB, keeping the hue when the new color
  /// is grey (where hue is undefined) so the hue slider doesn't jump.
  void _setColor(Color color, TextEditingController from) => setState(() {
        final next = HSVColor.fromColor(color);
        _hsv = next.saturation == 0 || next.value == 0 ? next.withHue(_hsv.hue) : next;
        _syncFields(skip: from);
      });

  void _onHex(String text) {
    final color = colorFromHex(text);
    if (color == null) {
      setState(() => _hexError = 'Use #RRGGBB');
    } else {
      _hexError = null;
      _setColor(color, _hex);
    }
  }

  void _onRgb(int index, String text) {
    final values = [for (final c in _rgb) int.tryParse(c.text) ?? 0];
    values[index] = (int.tryParse(text) ?? 0).clamp(0, 255);
    _setColor(Color.fromARGB(255, values[0], values[1], values[2]), _rgb[index]);
  }

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    final color = _color;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.checkReadability)
              _Preview(color: color)
            else
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ts.faint),
                ),
              ),
            const SizedBox(height: 16),
            _GradientSlider(
              label: 'Hue',
              value: _hsv.hue,
              max: 360,
              colors: [
                for (var h = 0; h <= 360; h += 60)
                  HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
              ],
              onChanged: (h) => _setHsv(_hsv.withHue(h)),
            ),
            _GradientSlider(
              label: 'Saturation',
              value: _hsv.saturation,
              max: 1,
              colors: [_hsv.withSaturation(0).toColor(), _hsv.withSaturation(1).toColor()],
              onChanged: (v) => _setHsv(_hsv.withSaturation(v)),
            ),
            _GradientSlider(
              label: 'Brightness',
              value: _hsv.value,
              max: 1,
              colors: [Colors.black, _hsv.withValue(1).toColor()],
              onChanged: (v) => _setHsv(_hsv.withValue(v)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hex,
              decoration: InputDecoration(labelText: 'Hex', errorText: _hexError),
              style: TerminalStyle.font.copyWith(color: ts.text),
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(7),
              ],
              onChanged: _onHex,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _rgb[i],
                      decoration: InputDecoration(labelText: const ['R', 'G', 'B'][i]),
                      style: TerminalStyle.font.copyWith(color: ts.text),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onChanged: (t) => _onRgb(i, t),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('Use color'),
        ),
      ],
    );
  }
}

/// Sample text in [color] on the dark and light backgrounds, with a warning
/// for any mode where it is hard to read.
class _Preview extends StatelessWidget {
  const _Preview({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget sample(TerminalStyle palette, String mode) {
      final ratio = contrastRatio(color, palette.background);
      final readable = ratio >= minReadableContrast;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.faint),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('mixin LenOS',
                  style: TerminalStyle.font.copyWith(color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                readable ? '$mode ✓' : '$mode: hard to read',
                style: TerminalStyle.font.copyWith(
                    fontSize: 11, color: readable ? palette.dim : palette.error),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        sample(TerminalStyle.dark, 'Dark'),
        const SizedBox(width: 8),
        sample(TerminalStyle.light, 'Light'),
      ],
    );
  }
}

/// A slider drawn over a gradient of what it controls.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.colors,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: ts.dim, fontSize: 12)),
        SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(colors: colors),
                    border: Border.all(color: ts.faint),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 14,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                ),
                child: Semantics(
                  label: label,
                  child: Slider(value: value.clamp(0, max), max: max, onChanged: onChanged),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

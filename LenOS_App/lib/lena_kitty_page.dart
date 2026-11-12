import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ascii_cat.dart';
import 'cat_personality.dart';
import 'terminal_style.dart';

/// Settings → Lena Kitty: weighting sliders for the choices in the cat's
/// behavior tree, with a live preview.
class LenaKittyPage extends StatelessWidget {
  const LenaKittyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final personality = context.watch<CatPersonality>();
    final ts = TerminalStyle.of(context);
    final theme = Theme.of(context);

    Widget group(String title, String when, bool atYarn) => Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(color: ts.accent)),
                Text(when, style: theme.textTheme.bodySmall?.copyWith(color: ts.dim)),
                const SizedBox(height: 8),
                for (final w in CatWeight.values.where((w) => w.atYarn == atYarn))
                  _WeightSlider(weight: w, personality: personality),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lena Kitty'),
        actions: [
          TextButton(
            onPressed: personality.weights == CatWeights.defaults
                ? null
                : personality.resetToDefaults,
            style: TextButton.styleFrom(
              foregroundColor: theme.appBarTheme.foregroundColor,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'How likely Lena Kitty is to pick each action. Higher means '
                    'more often; 0 means never. Sleeping when tired, chasing a '
                    'rolling yarn, and the reactions to taps always happen. Drag '
                    'the yarn to pick it up; drop it on her head for a bonk.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: ts.dim),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.pets),
                  title: const Text('Show on other pages'),
                  subtitle: const Text(
                      'Settings, Headspace Manager, Devices and File Manager, '
                      'behind everything else'),
                  value: personality.roams,
                  onChanged: (v) => personality.roams = v,
                ),
                group('At the yarn', 'When her paws reach the yarn', true),
                group('When idle', 'When there is nothing to chase', false),
              ],
            ),
          ),
          // A live preview with these weights.
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: ts.surface,
              border: Border(top: BorderSide(color: ts.faint)),
            ),
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Text('Preview: tap her!',
                      style: theme.textTheme.bodySmall?.copyWith(color: ts.dim)),
                  const AsciiCat(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightSlider extends StatelessWidget {
  const _WeightSlider({required this.weight, required this.personality});

  final CatWeight weight;
  final CatPersonality personality;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    final theme = Theme.of(context);
    final value = personality.weights[weight];
    final chance = (personality.weights.chanceOf(weight) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(weight.label, style: theme.textTheme.bodyLarge),
            if (weight.note != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text('(${weight.note})',
                    style: theme.textTheme.bodySmall?.copyWith(color: ts.dim),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
            const Spacer(),
            Text('${value.toStringAsFixed(1)} · $chance%',
                style: theme.textTheme.bodyMedium?.copyWith(color: ts.dim)),
          ],
        ),
        Slider(
          value: value,
          max: CatWeight.max,
          divisions: (CatWeight.max * 10).round(),
          label: value.toStringAsFixed(1),
          semanticFormatterCallback: (v) =>
              '${weight.label}: ${v.toStringAsFixed(1)}, $chance percent',
          onChanged: (v) => personality.set(weight, v),
          onChangeEnd: (_) => personality.save(),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'fs/fs_dialogs.dart';
import 'history.dart';
import 'terminal_style.dart';

/// Settings → History: everything in the [HistoryLog], newest first.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  static IconData iconFor(HistoryKind kind) => switch (kind) {
    HistoryKind.user => Icons.person,
    HistoryKind.read => Icons.download,
    HistoryKind.write => Icons.upload,
    HistoryKind.headspace => Icons.psychology,
    HistoryKind.file => Icons.description,
    HistoryKind.terminal => Icons.terminal,
    HistoryKind.bonk => Icons.pets,
  };

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryLog>();
    final entries = history.entries;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          TextButton(
            onPressed: entries.isEmpty
                ? null
                : () async {
                    final ok = await confirm(
                      context,
                      title: 'Clear history?',
                      message: 'Every entry in the History is removed.',
                      confirmLabel: 'Clear',
                      destructive: true,
                    );
                    if (ok) history.clear();
                  },
            style: TextButton.styleFrom(
              foregroundColor: theme.appBarTheme.foregroundColor,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing here yet.\nUSER changes, NFC reads and writes, '
                  'file changes, Terminal commands and Lena Kitty bonks '
                  'appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final newDay = i == 0 || !_sameDay(entries[i - 1].time, e.time);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (newDay) _DayHeader(e.time),
                    _EntryTile(entry: e),
                  ],
                );
              },
            ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String two(int n) => n.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        '${day.year}-${two(day.month)}-${two(day.day)}',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final ts = TerminalStyle.of(context);
    String two(int n) => n.toString().padLeft(2, '0');
    final t = entry.time;
    // Terminal commands are shown as typed, in the Terminal's font.
    final detailStyle = entry.kind == HistoryKind.terminal
        ? TerminalStyle.font.copyWith(color: ts.dim)
        : TextStyle(color: ts.dim);
    return ListTile(
      leading: Icon(HistoryPage.iconFor(entry.kind), color: ts.accent),
      title: entry.newDevice
          ? Row(
              children: [
                Flexible(child: Text(entry.title)),
                const SizedBox(width: 8),
                Text(
                  'NEW DEVICE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          : Text(entry.title),
      subtitle: entry.details.isEmpty
          ? null
          : SelectableText(entry.details.join('\n'), style: detailStyle),
      trailing: Text(
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
        style: TextStyle(color: ts.dim),
      ),
    );
  }
}

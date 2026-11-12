import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'code_editor_page.dart';
import 'file_manager_page.dart';
import 'fs/editor_session.dart';
import 'headspace_manager_page.dart';
import 'loaded_files_page.dart';
import 'terminal_page.dart';

/// The Home page's list of sections. The cards share the available height,
/// each taking [fillFraction] of its share, but never get shorter than
/// [minTileHeight] (the list scrolls instead, e.g. on small screens or in
/// landscape).
class HomeSectionList extends StatelessWidget {
  const HomeSectionList({
    super.key,
    required this.sections,
    this.footer,
    this.footerHeight = 0,
  });

  final List<Widget> sections;

  /// Shown on top of the list in the space below the cards (e.g. the cat),
  /// but only when the cards leave that much room, so it never covers or
  /// blocks them.
  final Widget? footer;
  final double footerHeight;

  static const _footerGap = 4.0;

  static const minTileHeight = 72.0;

  /// How much of its share of the screen each card uses.
  static const fillFraction = 0.85;
  static const maxTileHeight = 200.0;
  static const _listPadding = 8.0;
  static const _cardMargin = 8.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final perSection = (constraints.maxHeight - 2 * _listPadding) / sections.length;
      final height = ((perSection - 2 * _cardMargin) * fillFraction)
          .clamp(minTileHeight, maxTileHeight)
          .toDouble();
      final contentHeight =
          2 * _listPadding + sections.length * (height + 2 * _cardMargin);
      final footerFits =
          contentHeight + footerHeight + _footerGap <= constraints.maxHeight;
      return Stack(
        children: [
          _HomeTileHeight(
            height: height,
            child: ListView(
              // Keeps the scroll position when switching tabs and back.
              key: const PageStorageKey('home-sections'),
              padding: const EdgeInsets.symmetric(vertical: _listPadding),
              children: sections,
            ),
          ),
          if (footer != null && footerFits)
            Positioned(
              left: 0,
              right: 0,
              bottom: _footerGap,
              height: footerHeight,
              child: footer!,
            ),
        ],
      );
    });
  }
}

/// Passes the tile height from [HomeSectionList] down to each [HomeSection].
class _HomeTileHeight extends InheritedWidget {
  const _HomeTileHeight({required this.height, required super.child});

  final double height;

  @override
  bool updateShouldNotify(_HomeTileHeight old) => old.height != height;
}

/// Shared card used by every section on the Home page: an icon and a title,
/// sized to fill its share of the screen.
class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.title,
    required this.icon,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = context
            .dependOnInheritedWidgetOfExactType<_HomeTileHeight>()
            ?.height ??
        HomeSectionList.minTileHeight;
    // Icons grow with the card, within reason.
    final iconSize = (height * 0.4).clamp(28.0, 52.0);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The icon stays at the left so the icons line up down the page;
                // the title is centered across the whole card.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(icon, color: theme.colorScheme.primary, size: iconSize),
                ),
                Padding(
                  // Keeps a long title clear of the icon on both sides.
                  padding: EdgeInsets.symmetric(horizontal: iconSize + 12),
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
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

class HeadspaceManagerSection extends StatelessWidget {
  const HeadspaceManagerSection({super.key});

  @override
  Widget build(BuildContext context) =>
      HomeSection(
        title: 'Headspace Manager',
        icon: Icons.psychology,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HeadspaceManagerPage()),
        ),
      );
}

class LenOSCodeSection extends StatelessWidget {
  const LenOSCodeSection({super.key});

  @override
  Widget build(BuildContext context) =>
      HomeSection(
        title: 'LenOS Code',
        icon: Icons.code,
        // Reopens the editor with its tabs, or starts a new file if none are open.
        onTap: () {
          final session = context.read<EditorSession>();
          if (session.buffers.isEmpty) session.newFile();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CodeEditorPage()),
          );
        },
      );
}

class TerminalSection extends StatelessWidget {
  const TerminalSection({super.key});

  @override
  Widget build(BuildContext context) =>
      HomeSection(
        title: 'Terminal',
        icon: Icons.terminal,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TerminalPage()),
        ),
      );
}

class DevicesSection extends StatelessWidget {
  const DevicesSection({super.key});

  @override
  Widget build(BuildContext context) =>
      HomeSection(
        title: 'Devices',
        icon: Icons.nfc,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoadedFilesPage()),
        ),
      );
}

class CodebaseSection extends StatelessWidget {
  const CodebaseSection({super.key});

  @override
  Widget build(BuildContext context) =>
      HomeSection(
        title: 'File Manager',
        icon: Icons.account_tree,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FileManagerPage()),
        ),
      );
}

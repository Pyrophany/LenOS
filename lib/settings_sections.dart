import 'package:flutter/material.dart';

/// Shared card used by every section on the Home page: just an icon and a title.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(title, style: theme.textTheme.titleMedium),
            ],
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
      const SettingsSection(title: 'Headspace Manager', icon: Icons.psychology);
}

class LoadFromFileSection extends StatelessWidget {
  const LoadFromFileSection({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsSection(title: 'Load From File', icon: Icons.upload_file);
}

class LenOSCodeSection extends StatelessWidget {
  const LenOSCodeSection({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsSection(title: 'LenOS Code', icon: Icons.code);
}

class TerminalSection extends StatelessWidget {
  const TerminalSection({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsSection(title: 'Terminal', icon: Icons.terminal);
}

class LoadedFilesSection extends StatelessWidget {
  const LoadedFilesSection({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsSection(title: 'Loaded Files', icon: Icons.folder_open);
}

class CodebaseSection extends StatelessWidget {
  const CodebaseSection({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsSection(title: 'Codebase', icon: Icons.account_tree);
}

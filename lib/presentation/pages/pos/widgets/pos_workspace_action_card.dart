import 'package:flutter/material.dart';

/// Consistent navigation card for a single POS capability.
final class PosWorkspaceActionCard extends StatelessWidget {
  const PosWorkspaceActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final forwardIcon = Directionality.of(context) == TextDirection.rtl
        ? Icons.chevron_left_rounded
        : Icons.chevron_right_rounded;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.only(
          start: 16,
          end: 12,
          top: 4,
          bottom: 4,
        ),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.12),
          foregroundColor: accent,
          child: Icon(icon),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Icon(forwardIcon),
        onTap: onTap,
      ),
    );
  }
}

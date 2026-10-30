import 'package:flutter/material.dart';
import 'package:qayd/presentation/components/atomic/qayd_text.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';

class QaydEmptyState extends StatelessWidget {
  const QaydEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(SpacingTokens.md),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: scheme.primary.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            QaydText(
              title,
              slot: QaydTextStyleSlot.titleSmall,
              textAlign: TextAlign.center,
              color: scheme.onSurface,
            ),
            if (description != null) ...[
              const SizedBox(height: SpacingTokens.xs),
              QaydText(
                description!,
                slot: QaydTextStyleSlot.labelSmall,
                textAlign: TextAlign.center,
                color: scheme.onSurfaceVariant,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: SpacingTokens.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

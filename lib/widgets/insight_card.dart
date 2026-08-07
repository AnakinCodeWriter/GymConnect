import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Coloured icon + label + title + message card. Shared presentation for
/// the dashboard's recommendation and feel-insight cards (previously two
/// near-identical private widgets). Meaning is conveyed by icon and text,
/// not colour alone.
class InsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;

  /// Small category label above the title (e.g. "Recommended Next Step").
  final String label;
  final String title;
  final String message;

  const InsightCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        border: Border.all(color: color.withAlpha(80)),
        borderRadius: BorderRadius.circular(Corners.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: Insets.xs),
                Text(message, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Expandable "Why am I seeing this?" section (Phase 7). Renders the
/// human-readable facts derived from a typed analytics result - the
/// structured evidence itself lives on the result model (e.g.
/// ExerciseDetail.evidence); this widget is presentation only.
class EvidencePanel extends StatelessWidget {
  final String title;
  final List<String> facts;

  const EvidencePanel({
    super.key,
    this.title = 'Why am I seeing this?',
    required this.facts,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(Corners.lg),
      ),
      child: Theme(
        // remove the ExpansionTile's default dividers
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.info_outline, color: scheme.primary, size: 20),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            Insets.lg,
            0,
            Insets.lg,
            Insets.md,
          ),
          children: [
            for (final fact in facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: TextStyle(color: scheme.primary)),
                    Expanded(
                      child: Text(fact, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

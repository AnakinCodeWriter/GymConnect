import 'package:flutter/material.dart';

/// A horizontally scrollable row of chips showing the user's most frequent
/// exercise names. Tapping a chip calls [onTap] with that name (the screen
/// adds or extends an exercise card). Extracted in Phase 11, unchanged.
class RecentExercisesRow extends StatelessWidget {
  final List<String> names;
  final void Function(String) onTap;

  const RecentExercisesRow({
    super.key,
    required this.names,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Recent Exercises',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: names.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ActionChip(
              label: Text(names[i]),
              onPressed: () => onTap(names[i]),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

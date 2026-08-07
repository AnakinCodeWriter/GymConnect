import 'package:flutter/material.dart';

/// Shows the 1-5 star feel rating sheet and resolves with the chosen rating,
/// or null when dismissed (rating skipped). Extracted in Phase 11.
Future<int?> showFeelRatingSheet(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    // isDismissible defaults to true - tapping outside returns null
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const FeelRatingSheet(),
  );
}

/// Star picker for the post-save session feel rating. Tapping a star pops
/// the sheet with that value.
class FeelRatingSheet extends StatefulWidget {
  const FeelRatingSheet({super.key});

  @override
  State<FeelRatingSheet> createState() => _FeelRatingSheetState();
}

class _FeelRatingSheetState extends State<FeelRatingSheet> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'How did that feel?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final value = i + 1;
              final filled = _selected != null && value <= _selected!;
              return IconButton(
                icon: Icon(
                  filled ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 40,
                ),
                tooltip: 'Rate $value of 5',
                onPressed: () {
                  setState(() => _selected = value);
                  Navigator.pop(context, value);
                },
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a star to rate  •  tap outside to skip',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

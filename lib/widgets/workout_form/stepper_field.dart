import 'package:flutter/material.dart';

/// A numeric text field flanked by -/+ buttons (extracted from the log
/// workout screen in Phase 11). The buttons adjust the controller's value by
/// [delta], clamped at [min]; integer fields round, decimal fields trim a
/// trailing ".0" to one decimal place - unchanged stepper behaviour.
class StepperField extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  final double delta;
  final double min;
  final bool isInt;

  /// Used in button tooltips/semantics: 'Decrease [valueLabel]'.
  final String valueLabel;

  const StepperField({
    super.key,
    required this.controller,
    required this.suffix,
    required this.delta,
    required this.min,
    required this.isInt,
    required this.valueLabel,
  });

  void _adjust(double byDelta) {
    final current = double.tryParse(controller.text) ?? 0;
    final next = (current + byDelta).clamp(min, double.infinity);
    if (isInt) {
      controller.text = next.round().toString();
    } else {
      controller.text = next % 1 == 0
          ? next.toInt().toString()
          : next.toStringAsFixed(1);
    }
  }

  Widget _stepButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _stepButton(
          icon: Icons.remove,
          tooltip: 'Decrease $valueLabel',
          onTap: () => _adjust(-delta),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 2,
                vertical: 8,
              ),
              suffixText: suffix,
              suffixStyle: const TextStyle(fontSize: 11),
            ),
            keyboardType: isInt
                ? TextInputType.number
                : const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        _stepButton(
          icon: Icons.add,
          tooltip: 'Increase $valueLabel',
          onTap: () => _adjust(delta),
        ),
      ],
    );
  }
}

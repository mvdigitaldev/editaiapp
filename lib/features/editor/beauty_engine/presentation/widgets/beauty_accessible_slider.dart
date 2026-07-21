import 'package:flutter/material.dart';

/// Slider com rótulo, valor visível e semântica para leitor de tela (Sprint 26).
class BeautyAccessibleSlider extends StatelessWidget {
  const BeautyAccessibleSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.enabled = true,
    this.valueFormatter,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final ValueChanged<double>? onChanged;
  final String Function(double value)? valueFormatter;

  String _formatValue(double raw) {
    if (valueFormatter != null) {
      return valueFormatter!(raw);
    }
    final percent = ((raw - min) / (max - min) * 100).round();
    return '$percent%';
  }

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    final display = _formatValue(clamped);
    final theme = Theme.of(context);

    return Semantics(
      label: label,
      value: display,
      slider: true,
      enabled: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                display,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.disabledColor,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              trackHeight: 4,
            ),
            child: Slider(
              value: clamped,
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              onChanged: enabled ? onChanged : null,
              semanticFormatterCallback: (raw) => '$label, $display',
            ),
          ),
        ],
      ),
    );
  }
}

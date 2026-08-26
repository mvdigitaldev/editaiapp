import 'dart:math' as math;

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
    this.bipolar = false,
    this.trailing,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final ValueChanged<double>? onChanged;
  final String Function(double value)? valueFormatter;

  /// Centro = neutro. Sem percentagem; o preenchimento sai do meio (padrão Meitu).
  final bool bipolar;

  /// À direita do rótulo (ex.: Geral / Esquerda / Direita).
  final Widget? trailing;

  String _formatValue(double raw) {
    if (valueFormatter != null) {
      return valueFormatter!(raw);
    }
    if (bipolar) {
      if (raw.abs() < 1e-6) {
        return 'neutro';
      }
      return raw < 0 ? 'aumento' : 'redução';
    }
    final percent = ((raw - min) / (max - min) * 100).round();
    return '$percent%';
  }

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    final display = _formatValue(clamped);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: label,
          value: display,
          excludeSemantics: true,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              if (!bipolar)
                Text(
                  display,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.disabledColor,
                  ),
                ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            trackHeight: 4,
            trackShape:
                bipolar ? const _CenteredTrackShape() : const RoundedRectSliderTrackShape(),
            showValueIndicator: bipolar
                ? ShowValueIndicator.never
                : ShowValueIndicator.onlyForDiscrete,
          ),
          child: Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions,
            label: bipolar ? null : display,
            onChanged: enabled ? onChanged : null,
            semanticFormatterCallback: (raw) => '$label, ${_formatValue(raw)}',
          ),
        ),
      ],
    );
  }
}

/// Preenche a partir do centro até ao thumb. Marca o zero no meio.
class _CenteredTrackShape extends RoundedRectSliderTrackShape {
  const _CenteredTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final trackHeight = sliderTheme.trackHeight;
    if (trackHeight == null || trackHeight <= 0) {
      return;
    }
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(trackRect.height / 2);
    final inactive = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    ).evaluate(enableAnimation)!;
    final active = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    ).evaluate(enableAnimation)!;

    final canvas = context.canvas;
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = inactive,
    );

    final centerX = trackRect.center.dx;
    final left = math.min(centerX, thumbCenter.dx);
    final right = math.max(centerX, thumbCenter.dx);
    if ((right - left) > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, trackRect.top, right, trackRect.bottom),
          radius,
        ),
        Paint()..color = active,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, trackRect.center.dy),
          width: 2,
          height: trackRect.height + 6,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = active.withOpacity(0.9),
    );
  }
}

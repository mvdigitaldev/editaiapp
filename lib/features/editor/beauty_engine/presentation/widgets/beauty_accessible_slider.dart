import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';

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

  /// Centro = neutro. O preenchimento sai do meio (padrão Meitu).
  final bool bipolar;

  /// À direita do rótulo (ex.: Geral / Esquerda / Direita).
  final Widget? trailing;

  static const _thumbPad = 24.0;
  static const _numberSlot = 16.0;

  int _percent(double raw) {
    if (min < 0 && max > 0) {
      final span = math.max(min.abs(), max.abs());
      return (raw / span * 100).round();
    }
    return ((raw - min) / (max - min) * 100).round();
  }

  String _formatValue(double raw) {
    if (valueFormatter != null) {
      return valueFormatter!(raw);
    }
    return '${_percent(raw)}%';
  }

  String _formatNumber(double raw) {
    if (valueFormatter != null) {
      return valueFormatter!(raw);
    }
    return '${_percent(raw)}';
  }

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    final display = _formatValue(clamped);
    final number = _formatNumber(clamped);
    final theme = Theme.of(context);
    final numberColor = enabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.85)
        : theme.disabledColor;

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
              if (trailing != null) trailing!,
            ],
          ),
        ),
        SizedBox(
          height: 48 + _numberSlot,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final span = max - min;
              final t = span.abs() < 1e-9 ? 0.0 : (clamped - min) / span;
              final trackWidth = math.max(0.0, constraints.maxWidth - 2 * _thumbPad);
              final thumbX = _thumbPad + t * trackWidth;
              const numberWidth = 36.0;
              final numberLeft = (thumbX - numberWidth / 2).clamp(
                0.0,
                math.max(0.0, constraints.maxWidth - numberWidth),
              ).toDouble();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: numberLeft,
                    top: 0,
                    width: numberWidth,
                    height: _numberSlot,
                    child: Text(
                      number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: numberColor,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    top: _numberSlot,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 24),
                        trackHeight: 4,
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: theme.colorScheme.onSurface
                            .withValues(alpha: 0.22),
                        disabledActiveTrackColor:
                            AppColors.primary.withValues(alpha: 0.35),
                        disabledInactiveTrackColor: theme.colorScheme.onSurface
                            .withValues(alpha: 0.10),
                        trackShape: _BeautySliderTrackShape(bipolar: bipolar),
                        showValueIndicator: ShowValueIndicator.never,
                        year2023: true,
                        padding: EdgeInsets.zero,
                      ),
                      child: Slider(
                        value: clamped,
                        min: min,
                        max: max,
                        divisions: divisions,
                        onChanged: enabled ? onChanged : null,
                        semanticFormatterCallback: (raw) =>
                            '$label, ${_formatValue(raw)}',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Faixa sempre visível, com marcas de escala. Bipolar preenche a partir do centro.
class _BeautySliderTrackShape extends RoundedRectSliderTrackShape {
  const _BeautySliderTrackShape({this.bipolar = false});

  final bool bipolar;

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
    if (trackRect.width <= 0 || trackRect.height <= 0) {
      return;
    }

    final inactive = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    ).evaluate(enableAnimation)!;
    final active = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    ).evaluate(enableAnimation)!;

    final canvas = context.canvas;
    final radius = Radius.circular(trackRect.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = inactive,
    );

    if (bipolar) {
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
        Paint()..color = active.withValues(alpha: 0.9),
      );
    } else if (thumbCenter.dx - trackRect.left > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            trackRect.left,
            trackRect.top,
            thumbCenter.dx,
            trackRect.bottom,
          ),
          radius,
        ),
        Paint()..color = active,
      );
    }

    const count = 5;
    final tickColor = inactive.withValues(alpha: 0.85);
    final minor = Paint()
      ..color = tickColor
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final major = Paint()
      ..color = tickColor
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final x = trackRect.left + trackRect.width * t;
      final isMajor = i == 0 || i == count - 1 || (bipolar && i == 2);
      final h = isMajor ? 7.0 : 4.5;
      canvas.drawLine(
        Offset(x, trackRect.bottom + 3),
        Offset(x, trackRect.bottom + 3 + h),
        isMajor ? major : minor,
      );
    }
  }
}

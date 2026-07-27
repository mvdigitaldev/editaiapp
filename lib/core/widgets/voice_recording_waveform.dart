import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Visualizador tipo WhatsApp: barrinhas verticais que sobem com o volume
/// e uma “linha do tempo” que avança enquanto grava.
class VoiceRecordingWaveform extends StatefulWidget {
  const VoiceRecordingWaveform({
    super.key,
    required this.levelDb,
    required this.elapsed,
    this.barCount = 36,
    this.height = 36,
  });

  /// Nível em dB vindo do speech_to_text (ex.: -50 … 0).
  final double levelDb;

  /// Tempo desde o início da gravação.
  final Duration elapsed;

  final int barCount;
  final double height;

  /// Normaliza dB tipicamente negativo para 0..1.
  static double normalizeDb(double levelDb) {
    // iOS: ~-60..0 | Android às vezes ~-2..10
    if (levelDb > 0) {
      return (levelDb / 10).clamp(0.05, 1.0);
    }
    return ((levelDb + 55) / 55).clamp(0.05, 1.0);
  }

  @override
  State<VoiceRecordingWaveform> createState() => _VoiceRecordingWaveformState();
}

class _VoiceRecordingWaveformState extends State<VoiceRecordingWaveform> {
  late List<double> _bars;

  @override
  void initState() {
    super.initState();
    _bars = List<double>.filled(widget.barCount, 0.12);
  }

  @override
  void didUpdateWidget(covariant VoiceRecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.levelDb != widget.levelDb ||
        oldWidget.elapsed != widget.elapsed) {
      _pushLevel(VoiceRecordingWaveform.normalizeDb(widget.levelDb));
    }
  }

  void _pushLevel(double level) {
    // Suaviza um pouco e adiciona variação leve para parecer “vivo”
    final jitter = 0.04 * math.sin(widget.elapsed.inMilliseconds / 80);
    final value = (level + jitter).clamp(0.08, 1.0);
    setState(() {
      _bars = [..._bars.skip(1), value];
    });
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height + 8,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            _formatElapsed(widget.elapsed),
            style: const TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CustomPaint(
              painter: _WaveformPainter(levels: _bars),
              size: Size(double.infinity, widget.height),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.levels});

  final List<double> levels;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final paint = Paint()
      ..color = AppColors.error
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    final gap = size.width / levels.length;
    final midY = size.height / 2;
    final maxHalf = size.height * 0.45;

    for (var i = 0; i < levels.length; i++) {
      final x = gap * i + gap / 2;
      final half = maxHalf * levels[i];
      canvas.drawLine(
        Offset(x, midY - half),
        Offset(x, midY + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.levels != levels;
  }
}

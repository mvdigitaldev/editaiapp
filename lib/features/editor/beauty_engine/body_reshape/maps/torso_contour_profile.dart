import 'dart:ui';

/// Faixa horizontal do torso com bordas esquerda/direita da silhueta.
class TorsoContourBand {
  const TorsoContourBand({
    required this.t,
    required this.y,
    required this.leftX,
    required this.rightX,
    required this.confidence,
    this.rejected = false,
  });

  /// Posição normalizada ombro→quadril [0,1].
  final double t;

  /// Coordenada Y em pixels da imagem.
  final double y;

  final double leftX;
  final double rightX;
  final double confidence;
  final bool rejected;

  double get width => (rightX - leftX).clamp(0.0, double.infinity);

  double get halfWidth => width * 0.5;

  double get midlineX => (leftX + rightX) * 0.5;

  TorsoContourBand copyWith({
    double? t,
    double? y,
    double? leftX,
    double? rightX,
    double? confidence,
    bool? rejected,
  }) {
    return TorsoContourBand(
      t: t ?? this.t,
      y: y ?? this.y,
      leftX: leftX ?? this.leftX,
      rightX: rightX ?? this.rightX,
      confidence: confidence ?? this.confidence,
      rejected: rejected ?? this.rejected,
    );
  }
}

/// Perfil denso do contorno do torso derivado da máscara de pessoa.
class TorsoContourProfile {
  const TorsoContourProfile({
    required this.bands,
    required this.topMid,
    required this.bottomMid,
    required this.imageSize,
    this.meanConfidence = 0,
    this.hasArmContamination = false,
  });

  final List<TorsoContourBand> bands;
  final Offset topMid;
  final Offset bottomMid;
  final Size imageSize;
  final double meanConfidence;
  final bool hasArmContamination;

  bool get isEmpty => bands.isEmpty;

  List<TorsoContourBand> get usableBands =>
      bands.where((band) => !band.rejected && band.width > 1).toList();

  /// Interpola a banda no parâmetro [t] (ombro→quadril).
  TorsoContourBand? sampleAt(double t) {
    final usable = usableBands;
    if (usable.isEmpty) {
      return null;
    }
    final clamped = t.clamp(0.0, 1.0);
    if (usable.length == 1) {
      return usable.first;
    }

    if (clamped <= usable.first.t) {
      return usable.first;
    }
    if (clamped >= usable.last.t) {
      return usable.last;
    }

    for (var i = 0; i < usable.length - 1; i++) {
      final a = usable[i];
      final b = usable[i + 1];
      if (clamped < a.t || clamped > b.t) {
        continue;
      }
      final span = (b.t - a.t).abs();
      final u = span < 1e-6 ? 0.0 : (clamped - a.t) / span;
      return TorsoContourBand(
        t: clamped,
        y: a.y + (b.y - a.y) * u,
        leftX: a.leftX + (b.leftX - a.leftX) * u,
        rightX: a.rightX + (b.rightX - a.rightX) * u,
        confidence: a.confidence + (b.confidence - a.confidence) * u,
      );
    }
    return usable.last;
  }

  /// Semi-largura local na altura [y] (pixels).
  double? halfWidthAtY(double y) {
    final span = (bottomMid.dy - topMid.dy).abs();
    if (span < 1) {
      return null;
    }
    final t = ((y - topMid.dy) / span).clamp(0.0, 1.0);
    return sampleAt(t)?.halfWidth;
  }

  /// Bordas esquerda/direita na altura [y].
  (double, double)? edgesAtY(double y) {
    final span = (bottomMid.dy - topMid.dy).abs();
    if (span < 1) {
      return null;
    }
    final t = ((y - topMid.dy) / span).clamp(0.0, 1.0);
    final band = sampleAt(t);
    if (band == null) {
      return null;
    }
    return (band.leftX, band.rightX);
  }
}

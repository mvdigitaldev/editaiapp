import 'dart:ui';

/// Par de pontos de controle source → target para MLS.
class ControlPoint {
  final Offset source;
  final Offset target;

  const ControlPoint({
    required this.source,
    required this.target,
  });

  Offset get delta => Offset(
        target.dx - source.dx,
        target.dy - source.dy,
      );

  bool get isAnchor => source == target;
}

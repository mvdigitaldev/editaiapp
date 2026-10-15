import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../warp/v2/displacement_field.dart';

/// Codifica um [DisplacementField] denso no RG que o shader de remap lê.
///
/// `channel = clamp(v / scale * 0.5 + 0.5)`. O shader faz
/// `(rg * 2 - 1) * scale * amplitude`. Com [amplitude] 1 o deslocamento
/// volta ao campo. O arrasto guarda o campo do início do gesto e varia
/// só a amplitude.
abstract final class DenseDisplacementPack {
  static ({Uint8List rgba, Offset scale}) pack(DisplacementField field) {
    var maxX = 0.0;
    var maxY = 0.0;
    final count = field.pixelCount;
    for (var i = 0; i < count; i++) {
      maxX = math.max(maxX, field.dx[i].abs());
      maxY = math.max(maxY, field.dy[i].abs());
    }
    final scale = Offset(
      math.max(1.0, maxX * 1.05),
      math.max(1.0, maxY * 1.05),
    );
    final rgba = Uint8List(count * 4);
    for (var i = 0; i < count; i++) {
      final o = i * 4;
      rgba[o] = _encode(field.dx[i] / scale.dx);
      rgba[o + 1] = _encode(field.dy[i] / scale.dy);
      rgba[o + 3] = 255;
    }
    return (rgba: rgba, scale: scale);
  }

  /// Inverso de [pack], para o teste. [amplitude] é o uniform do shader.
  static Offset decode({
    required int encodedX,
    required int encodedY,
    required Offset scale,
    double amplitude = 1,
  }) {
    final dx = (encodedX / 255.0 * 2.0 - 1.0) * scale.dx * amplitude;
    final dy = (encodedY / 255.0 * 2.0 - 1.0) * scale.dy * amplitude;
    return Offset(dx, dy);
  }

  static int _encode(double signedUnit) {
    final channel = (signedUnit.clamp(-1.0, 1.0) * 0.5 + 0.5) * 255.0;
    return channel.round().clamp(0, 255);
  }
}

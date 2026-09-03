import 'dart:math' as math;
import 'dart:typed_data';

import 'displacement_field.dart';

/// Pedido do renderer V2. Nomes neste library; o `WarpRequest` MLS vive noutro
/// sítio e não se reutiliza (exige `TriMesh`).
class WarpRequest {
  const WarpRequest({
    required this.sourceRgba,
    required this.width,
    required this.height,
    required this.field,
  });

  final Uint8List sourceRgba;
  final int width;
  final int height;
  final DisplacementField field;
}

/// `rgba` é `v2Raw`. Origem inválida preserva o destino e marca as máscaras;
/// não há clamp para a borda da fonte.
class WarpResult {
  WarpResult({
    required this.rgba,
    required this.coverage,
    required this.invalidSource,
  });

  final Uint8List rgba;
  final Uint8List coverage;
  final Uint8List invalidSource;
}

/// Remap backward bilinear isolado. Sem landmarks, máscaras, fill ou V1.
///
/// Convenção: `source = destination - displacement`.
/// Origem válida: `src` no rect fechado `[0, width-1] × [0, height-1]`.
/// Origem inválida: não amostra; RGBA de destino inalterado; `coverage=0`;
/// `invalidSource=1`.
///
/// Onde o remap **comprime** a imagem, um passo de um pixel no destino salta
/// mais de um pixel na origem, e a bilinear, que só lê o quadrado `2×2`, deixa
/// cair o que fica no meio: é aliasing, e nas bordas de contraste lê-se como
/// serrilhado. Com um campo facial no extremo isso apanha mais de 40% dos
/// pixels deslocados, com até 1,43× de compressão. Esses pixels são amostrados
/// por área, numa grelha de sub-amostras dentro do pixel de destino, o que face
/// ao filtro de área exacto baixa o erro de 33 para 2,8 níveis de 255. Quem não
/// comprime segue pela bilinear simples e sai byte a byte igual.
abstract final class BackwardBilinearWarp {
  BackwardBilinearWarp._();

  /// Compressão a partir da qual se filtra por área. Um pouco acima de um para
  /// não pagar supersampling onde a perda é irrelevante.
  static const _minificationFloor = 1.05;

  /// Sub-amostras por eixo, no máximo. Com `3` cobre-se compressão até 3×, e a
  /// dos seis efeitos no extremo não passa de 1,5×.
  static const _maxSamplesPerAxis = 3;

  static WarpResult apply(WarpRequest request) {
    final width = request.width;
    final height = request.height;
    final source = request.sourceRgba;
    final field = request.field;
    final expectedBytes = width * height * 4;
    if (width <= 0 || height <= 0) {
      throw ArgumentError('warp_invalid_size: ${width}x$height');
    }
    if (source.length != expectedBytes) {
      throw StateError(
        'rgba_buffer_size_mismatch: got ${source.length}, expected $expectedBytes',
      );
    }
    if (field.width != width || field.height != height) {
      throw StateError(
        'displacement_field_size_mismatch: field ${field.width}x${field.height} '
        'image ${width}x$height',
      );
    }

    final pixelCount = width * height;
    final rgba = Uint8List.fromList(source);
    final coverage = Uint8List(pixelCount);
    final invalidSource = Uint8List(pixelCount);
    final maxX = width - 1;
    final maxY = height - 1;

    // Onde o campo e os seus oito vizinhos são nulos, a jacobiana é a
    // identidade, o remap devolve `src = p` e a bilinear em posição inteira lê
    // um só tap: o destino é o pixel de origem, que já está copiado. Esses
    // pixels ficam cobertos e válidos sem se calcular nada. Um campo facial
    // costuma ser nulo em mais de três quartos da imagem.
    final support = _support(field, width, height);
    if (support == null) {
      coverage.fillRange(0, pixelCount, 255);
      return WarpResult(
        rgba: rgba,
        coverage: coverage,
        invalidSource: invalidSource,
      );
    }
    coverage.fillRange(0, pixelCount, 255);

    for (var y = support.top; y <= support.bottom; y++) {
      for (var x = support.left; x <= support.right; x++) {
        final i = y * width + x;
        final srcX = x - field.dx[i];
        final srcY = y - field.dy[i];
        if (srcX < 0 || srcY < 0 || srcX > maxX || srcY > maxY) {
          invalidSource[i] = 1;
          coverage[i] = 0;
          continue;
        }
        coverage[i] = 255;
        invalidSource[i] = 0;
        final samples = _samplesPerAxis(field, x, y, width, height);
        if (samples <= 1) {
          _writeBilinear(rgba, source, width, height, i * 4, srcX, srcY);
        } else {
          _writeAreaAveraged(
            dst: rgba,
            src: source,
            width: width,
            height: height,
            field: field,
            dstIdx: i * 4,
            x: x,
            y: y,
            samplesPerAxis: samples,
          );
        }
      }
    }

    return WarpResult(
      rgba: rgba,
      coverage: coverage,
      invalidSource: invalidSource,
    );
  }

  /// Caixa que contém todo o deslocamento não nulo, dilatada de um pixel para
  /// abranger os vizinhos que a jacobiana lê. `null` se o campo for nulo.
  static ({int left, int top, int right, int bottom})? _support(
    DisplacementField field,
    int width,
    int height,
  ) {
    final dx = field.dx;
    final dy = field.dy;
    var left = width;
    var top = height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final i = row + x;
        if (dx[i] == 0 && dy[i] == 0) {
          continue;
        }
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        bottom = y;
      }
    }
    if (right < 0) {
      return null;
    }
    return (
      left: left > 0 ? left - 1 : 0,
      top: top > 0 ? top - 1 : 0,
      right: right < width - 1 ? right + 1 : width - 1,
      bottom: bottom < height - 1 ? bottom + 1 : height - 1,
    );
  }

  /// Sub-amostras por eixo que o pixel `(x, y)` precisa, ou `1` para seguir
  /// pela bilinear simples.
  ///
  /// O remap é `src = p − D(p)`, logo a sua jacobiana é `A = I − JD`, e o passo
  /// que um pixel do destino dá na origem é o maior valor singular de `A`.
  /// Acima de um, a bilinear não chega.
  static int _samplesPerAxis(
    DisplacementField field,
    int x,
    int y,
    int width,
    int height,
  ) {
    // Sem vizinhos não há derivada; a moldura da imagem não é onde os efeitos
    // faciais actuam.
    if (x < 1 || y < 1 || x + 1 >= width || y + 1 >= height) {
      return 1;
    }
    final i = y * width + x;
    final dx = field.dx;
    final dy = field.dy;
    final a = 1 - (dx[i + 1] - dx[i - 1]) * 0.5;
    final b = -(dx[i + width] - dx[i - width]) * 0.5;
    final c = -(dy[i + 1] - dy[i - 1]) * 0.5;
    final d = 1 - (dy[i + width] - dy[i - width]) * 0.5;
    // Valores singulares de uma 2×2 a partir da norma de Frobenius e do
    // determinante, sem decomposição.
    final frobenius = a * a + b * b + c * c + d * d;
    final determinant = a * d - b * c;
    final discriminant =
        frobenius * frobenius - 4 * determinant * determinant;
    final root = discriminant > 0 ? math.sqrt(discriminant) : 0.0;
    final largest = math.sqrt((frobenius + root) * 0.5);
    if (largest <= _minificationFloor) {
      return 1;
    }
    final needed = largest.ceil();
    return needed < _maxSamplesPerAxis ? needed : _maxSamplesPerAxis;
  }

  /// Média das amostras de uma grelha dentro do pixel de destino, que é o
  /// filtro de área da sua pré-imagem.
  ///
  /// O campo é lido interpolado nas sub-posições: é denso e liso, portanto
  /// interpolá-lo é fiel. Sub-amostra com origem fora do rect é descartada da
  /// média em vez de presa à borda, para manter a regra de não fazer clamp da
  /// coordenada de origem. Se todas caírem fora o destino fica intacto.
  static void _writeAreaAveraged({
    required Uint8List dst,
    required Uint8List src,
    required int width,
    required int height,
    required DisplacementField field,
    required int dstIdx,
    required int x,
    required int y,
    required int samplesPerAxis,
  }) {
    final maxX = width - 1;
    final maxY = height - 1;
    final step = 1.0 / samplesPerAxis;
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    var alpha = 0.0;
    var taken = 0;
    for (var sy = 0; sy < samplesPerAxis; sy++) {
      final py = y + (sy + 0.5) * step - 0.5;
      for (var sx = 0; sx < samplesPerAxis; sx++) {
        final px = x + (sx + 0.5) * step - 0.5;
        final srcX = px - _sampleField(field.dx, width, height, px, py);
        final srcY = py - _sampleField(field.dy, width, height, px, py);
        if (srcX < 0 || srcY < 0 || srcX > maxX || srcY > maxY) {
          continue;
        }
        final x0 = srcX.floor();
        final y0 = srcY.floor();
        final x1 = x0 + 1 < width ? x0 + 1 : x0;
        final y1 = y0 + 1 < height ? y0 + 1 : y0;
        final tx = srcX - x0;
        final ty = srcY - y0;
        final i00 = (y0 * width + x0) * 4;
        final i10 = (y0 * width + x1) * 4;
        final i01 = (y1 * width + x0) * 4;
        final i11 = (y1 * width + x1) * 4;
        r += _bilinear(src, i00, i10, i01, i11, 0, tx, ty);
        g += _bilinear(src, i00, i10, i01, i11, 1, tx, ty);
        b += _bilinear(src, i00, i10, i01, i11, 2, tx, ty);
        alpha += _bilinear(src, i00, i10, i01, i11, 3, tx, ty);
        taken++;
      }
    }
    if (taken == 0) {
      return;
    }
    final norm = 1.0 / taken;
    dst[dstIdx] = (r * norm).round().clamp(0, 255);
    dst[dstIdx + 1] = (g * norm).round().clamp(0, 255);
    dst[dstIdx + 2] = (b * norm).round().clamp(0, 255);
    dst[dstIdx + 3] = (alpha * norm).round().clamp(0, 255);
  }

  /// Uma componente do campo numa posição fraccionária. Fora da grelha o campo
  /// vale zero, que é o que o contrato diz do exterior do domínio.
  static double _sampleField(
    Float32List component,
    int width,
    int height,
    double px,
    double py,
  ) {
    if (px < 0 || py < 0 || px > width - 1 || py > height - 1) {
      return 0;
    }
    final x0 = px.floor();
    final y0 = py.floor();
    final x1 = x0 + 1 < width ? x0 + 1 : x0;
    final y1 = y0 + 1 < height ? y0 + 1 : y0;
    final tx = px - x0;
    final ty = py - y0;
    final top = _lerp(
      component[y0 * width + x0],
      component[y0 * width + x1],
      tx,
    );
    final bottom = _lerp(
      component[y1 * width + x0],
      component[y1 * width + x1],
      tx,
    );
    return _lerp(top, bottom, ty);
  }

  static double _bilinear(
    Uint8List src,
    int i00,
    int i10,
    int i01,
    int i11,
    int c,
    double tx,
    double ty,
  ) =>
      _lerp(
        _lerp(src[i00 + c].toDouble(), src[i10 + c].toDouble(), tx),
        _lerp(src[i01 + c].toDouble(), src[i11 + c].toDouble(), tx),
        ty,
      );

  /// Amostra só com origem já validada. Na última coluna/linha os taps
  /// coincidem (bilinear degenerado) — isso não é clamp de coordenada OOB.
  static void _writeBilinear(
    Uint8List dst,
    Uint8List src,
    int width,
    int height,
    int dstIdx,
    double srcX,
    double srcY,
  ) {
    final x0 = srcX.floor();
    final y0 = srcY.floor();
    final x1 = x0 + 1 < width ? x0 + 1 : x0;
    final y1 = y0 + 1 < height ? y0 + 1 : y0;
    final tx = srcX - x0;
    final ty = srcY - y0;
    final i00 = (y0 * width + x0) * 4;
    final i10 = (y0 * width + x1) * 4;
    final i01 = (y1 * width + x0) * 4;
    final i11 = (y1 * width + x1) * 4;
    for (var c = 0; c < 4; c++) {
      final v = _lerp(
        _lerp(src[i00 + c].toDouble(), src[i10 + c].toDouble(), tx),
        _lerp(src[i01 + c].toDouble(), src[i11 + c].toDouble(), tx),
        ty,
      );
      dst[dstIdx + c] = v.round().clamp(0, 255);
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

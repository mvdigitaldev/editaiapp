import 'dart:math' as math;
import 'dart:typed_data';

import '../../../segment/person_mask.dart';
import '../displacement_field.dart';

/// Recorte da imagem onde a trava trabalha, com o alfa e o fundo limpo dele.
class BodyBackgroundLockPrepared {
  BodyBackgroundLockPrepared({
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.alpha,
    required this.plate,
    required this.background,
    required this.filled,
  });

  final int width;
  final int height;

  /// Recorte fechado em coordenadas da imagem.
  final int left;
  final int top;
  final int right;
  final int bottom;

  int get roiWidth => right - left + 1;
  int get roiHeight => bottom - top + 1;

  /// Alfa da pessoa 0..1 no recorte.
  final Float32List alpha;

  /// RGBA do fundo limpo no recorte: origem no fundo, preenchido junto à borda
  /// por dentro da pessoa, origem no resto.
  final Uint8List plate;

  /// 1 onde a origem já era fundo seguro: aí o fundo limpo é a própria origem.
  final Uint8List background;

  /// Pixels do recorte cujo fundo foi inventado.
  final int filled;
}

/// Cache do alfa refinado e do fundo limpo. O slider nunca os refaz.
class BodyBackgroundLockRuntime {
  Uint8List? source;
  PersonMask? mask;
  List<DisplacementField> fields = const [];
  int width = 0;
  int height = 0;
  int bandPx = 0;
  BodyBackgroundLockPrepared? prepared;

  /// Quantas vezes o fundo limpo foi construído; os testes contam o cache.
  int builds = 0;

  bool matches(
    Uint8List source,
    PersonMask mask,
    List<DisplacementField> fields,
    int width,
    int height,
    int bandPx,
  ) {
    if (prepared == null ||
        !identical(this.source, source) ||
        !identical(this.mask, mask) ||
        this.width != width ||
        this.height != height ||
        this.bandPx != bandPx ||
        this.fields.length != fields.length) {
      return false;
    }
    for (var i = 0; i < fields.length; i++) {
      if (!identical(this.fields[i], fields[i])) {
        return false;
      }
    }
    return true;
  }
}

/// Trava de fundo do corpo.
///
/// A pessoa leva o alfa no canal A pelo mesmo remap da cor; no fim compõe-se
/// sobre o fundo limpo: `out = rgb' + λ · (1 − a') · (fundo − rgb')`. Onde a
/// origem já era fundo, `λ = 1` e o pixel volta exactamente à origem. Onde o
/// fundo foi inventado, `λ = smoothstep(|D| / 0.25 px)`: sem movimento a borda
/// da pessoa fica como estava.
abstract final class BodyBackgroundLock {
  BodyBackgroundLock._();

  static const guidedRadius = 2;
  static const guidedEps = 1e-3;

  /// O guided filter só decide a ±[trimapRadius] px da borda da máscara: num
  /// fundo com textura forte ele copia as arestas da luma e espalharia alfa
  /// pelo fundo, e o fundo com alfa acima de zero é arrastado com o corpo.
  static const trimapRadius = 1;

  /// Abaixo disto o pixel é fundo seguro.
  static const backgroundAlpha = 0.04;

  /// `|D|` a partir do qual a composição vale por inteiro.
  static const fullLockDisplacement = 0.25;

  static BodyBackgroundLockPrepared? prepare({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required PersonMask mask,
    required List<DisplacementField> fields,
    required int bandPx,
    BodyBackgroundLockRuntime? runtime,
  }) {
    if (fields.isEmpty ||
        sourceRgba.length != width * height * 4 ||
        mask.width <= 0 ||
        mask.height <= 0 ||
        mask.bytes.length < mask.width * mask.height) {
      return null;
    }
    if (runtime != null &&
        runtime.matches(sourceRgba, mask, fields, width, height, bandPx)) {
      return runtime.prepared;
    }

    final support = _support(fields, width, height, bandPx + 2);
    if (support == null) {
      return null;
    }
    final prepared = _build(
      sourceRgba: sourceRgba,
      width: width,
      height: height,
      mask: mask,
      left: support.left,
      top: support.top,
      right: support.right,
      bottom: support.bottom,
      bandPx: bandPx,
    );
    if (runtime != null) {
      runtime
        ..source = sourceRgba
        ..mask = mask
        ..fields = List<DisplacementField>.of(fields)
        ..width = width
        ..height = height
        ..bandPx = bandPx
        ..prepared = prepared
        ..builds += 1;
    }
    return prepared;
  }

  /// Cópia da origem com o alfa da pessoa no canal A dentro do recorte.
  static Uint8List packAlpha(
    Uint8List sourceRgba,
    BodyBackgroundLockPrepared prepared,
  ) {
    final out = Uint8List.fromList(sourceRgba);
    final rw = prepared.roiWidth;
    for (var y = prepared.top; y <= prepared.bottom; y++) {
      final row = (y - prepared.top) * rw;
      for (var x = prepared.left; x <= prepared.right; x++) {
        final a = prepared.alpha[row + x - prepared.left];
        out[(y * prepared.width + x) * 4 + 3] = (a * 255).round();
      }
    }
    return out;
  }

  /// Compõe a pessoa deformada (alfa em A) sobre o fundo limpo. Devolve A=255.
  static Uint8List composite({
    required Uint8List warpedRgba,
    required BodyBackgroundLockPrepared prepared,
    required List<DisplacementField> fields,
  }) {
    final out = warpedRgba;
    final w = prepared.width;
    final rw = prepared.roiWidth;
    for (var y = prepared.top; y <= prepared.bottom; y++) {
      final row = (y - prepared.top) * rw;
      for (var x = prepared.left; x <= prepared.right; x++) {
        final i = y * w + x;
        final o = i * 4;
        final a = out[o + 3] / 255.0;
        out[o + 3] = 255;
        if (a >= 1) {
          continue;
        }
        final local = row + x - prepared.left;
        double motion;
        if (prepared.background[local] == 1) {
          motion = 1;
        } else {
          var d2 = 0.0;
          for (final f in fields) {
            final m = f.dx[i] * f.dx[i] + f.dy[i] * f.dy[i];
            if (m > d2) {
              d2 = m;
            }
          }
          if (d2 <= 0) {
            continue;
          }
          final q = math.min(1.0, math.sqrt(d2) / fullLockDisplacement);
          motion = q * q * (3 - 2 * q);
        }
        final lambda = motion * (1 - a);
        final p = local * 4;
        for (var c = 0; c < 3; c++) {
          final v = out[o + c];
          out[o + c] = (v + lambda * (prepared.plate[p + c] - v))
              .round()
              .clamp(0, 255);
        }
      }
    }
    for (var i = 3; i < out.length; i += 4) {
      out[i] = 255;
    }
    return out;
  }

  /// Caixa dos pixels com campo, dilatada de [margin].
  static ({int left, int top, int right, int bottom})? _support(
    List<DisplacementField> fields,
    int width,
    int height,
    int margin,
  ) {
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (final f in fields) {
      for (var y = 0; y < height; y++) {
        final row = y * width;
        for (var x = 0; x < width; x++) {
          final i = row + x;
          if (f.dx[i] != 0 || f.dy[i] != 0) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
    }
    if (maxX < 0) {
      return null;
    }
    return (
      left: math.max(0, minX - margin),
      top: math.max(0, minY - margin),
      right: math.min(width - 1, maxX + margin),
      bottom: math.min(height - 1, maxY + margin),
    );
  }

  static BodyBackgroundLockPrepared _build({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required PersonMask mask,
    required int left,
    required int top,
    required int right,
    required int bottom,
    required int bandPx,
  }) {
    final rw = right - left + 1;
    final rh = bottom - top + 1;
    final n = rw * rh;

    final luma = Float32List(n);
    final coarse = Float32List(n);
    for (var y = 0; y < rh; y++) {
      final iy = y + top;
      for (var x = 0; x < rw; x++) {
        final ix = x + left;
        final o = (iy * width + ix) * 4;
        luma[y * rw + x] = (0.299 * sourceRgba[o] +
                0.587 * sourceRgba[o + 1] +
                0.114 * sourceRgba[o + 2]) /
            255.0;
        coarse[y * rw + x] = mask.sampleNormalized(
          (ix + 0.5) / width,
          (iy + 0.5) / height,
        );
      }
    }
    final guided =
        _guidedFilter(luma, coarse, rw, rh, guidedRadius, guidedEps);
    final near = _boxMean(coarse, rw, rh, trimapRadius);
    final alpha = Float32List(n);
    for (var i = 0; i < n; i++) {
      final m = near[i];
      alpha[i] = m <= 1e-4
          ? 0
          : m >= 1 - 1e-4
              ? 1
              : guided[i];
    }

    final plate = Uint8List(n * 4);
    for (var y = 0; y < rh; y++) {
      final src = ((y + top) * width + left) * 4;
      plate.setRange(y * rw * 4, (y + 1) * rw * 4, sourceRgba, src);
    }
    final background = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (alpha[i] < backgroundAlpha) {
        background[i] = 1;
      }
    }
    final filled = _onionFill(plate, alpha, rw, rh, bandPx);

    return BodyBackgroundLockPrepared(
      width: width,
      height: height,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      alpha: alpha,
      plate: plate,
      background: background,
      filled: filled,
    );
  }

  /// Guided filter de cinzento (He et al.): a borda do alfa segue a da imagem.
  static Float32List _guidedFilter(
    Float32List guide,
    Float32List input,
    int w,
    int h,
    int r,
    double eps,
  ) {
    final n = w * h;
    final ip = Float32List(n);
    final ii = Float32List(n);
    for (var i = 0; i < n; i++) {
      ip[i] = guide[i] * input[i];
      ii[i] = guide[i] * guide[i];
    }
    final meanI = _boxMean(guide, w, h, r);
    final meanP = _boxMean(input, w, h, r);
    final corrIp = _boxMean(ip, w, h, r);
    final corrII = _boxMean(ii, w, h, r);
    final a = Float32List(n);
    final b = Float32List(n);
    for (var i = 0; i < n; i++) {
      final varI = corrII[i] - meanI[i] * meanI[i];
      final covIp = corrIp[i] - meanI[i] * meanP[i];
      a[i] = covIp / (varI + eps);
      b[i] = meanP[i] - a[i] * meanI[i];
    }
    final meanA = _boxMean(a, w, h, r);
    final meanB = _boxMean(b, w, h, r);
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = (meanA[i] * guide[i] + meanB[i]).clamp(0.0, 1.0);
    }
    return out;
  }

  /// Média em caixa `(2r+1)²` por imagem integral, com a caixa recortada.
  static Float32List _boxMean(Float32List v, int w, int h, int r) {
    final sw = w + 1;
    final sat = Float64List(sw * (h + 1));
    for (var y = 0; y < h; y++) {
      var rowSum = 0.0;
      for (var x = 0; x < w; x++) {
        rowSum += v[y * w + x];
        sat[(y + 1) * sw + x + 1] = sat[y * sw + x + 1] + rowSum;
      }
    }
    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r);
      final y1 = math.min(h - 1, y + r);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - r);
        final x1 = math.min(w - 1, x + r);
        final sum = sat[(y1 + 1) * sw + x1 + 1] -
            sat[y0 * sw + x1 + 1] -
            sat[(y1 + 1) * sw + x0] +
            sat[y0 * sw + x0];
        out[y * w + x] = sum / ((y1 - y0 + 1) * (x1 - x0 + 1));
      }
    }
    return out;
  }

  /// Preenche, anel a anel e de fora para dentro, até [band] px por dentro da
  /// pessoa: cada pixel recebe a média dos vizinhos já conhecidos. Depois uma
  /// caixa 3×3 só nos preenchidos tira o padrão dos anéis.
  static int _onionFill(
    Uint8List plate,
    Float32List alpha,
    int w,
    int h,
    int band,
  ) {
    final n = w * h;
    final known = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (alpha[i] < backgroundAlpha) {
        known[i] = 1;
      }
    }
    final filledMask = Uint8List(n);
    var frontier = <int>[];
    for (var i = 0; i < n; i++) {
      if (known[i] == 0 && _hasKnownNeighbour(known, i % w, i ~/ w, w, h)) {
        frontier.add(i);
      }
    }
    var filled = 0;
    final colors = Float64List(4);
    for (var ring = 0; ring < band && frontier.isNotEmpty; ring++) {
      final values = Uint8List(frontier.length * 3);
      for (var k = 0; k < frontier.length; k++) {
        final i = frontier[k];
        final x = i % w;
        final y = i ~/ w;
        colors.fillRange(0, 4, 0);
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if ((dx == 0 && dy == 0) || nx < 0 || nx >= w) continue;
            final j = ny * w + nx;
            if (known[j] == 0) continue;
            colors[0] += plate[j * 4];
            colors[1] += plate[j * 4 + 1];
            colors[2] += plate[j * 4 + 2];
            colors[3] += 1;
          }
        }
        for (var c = 0; c < 3; c++) {
          values[k * 3 + c] = (colors[c] / colors[3]).round();
        }
      }
      final next = <int>[];
      for (var k = 0; k < frontier.length; k++) {
        final i = frontier[k];
        plate[i * 4] = values[k * 3];
        plate[i * 4 + 1] = values[k * 3 + 1];
        plate[i * 4 + 2] = values[k * 3 + 2];
        known[i] = 1;
        filledMask[i] = 1;
        filled++;
      }
      for (final i in frontier) {
        final x = i % w;
        final y = i ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w) continue;
            final j = ny * w + nx;
            if (known[j] == 0 && filledMask[j] == 0) {
              filledMask[j] = 2;
              next.add(j);
            }
          }
        }
      }
      for (final j in next) {
        filledMask[j] = 0;
      }
      frontier = next;
    }

    final smooth = Uint8List.fromList(plate);
    for (var i = 0; i < n; i++) {
      if (filledMask[i] != 1) continue;
      final x = i % w;
      final y = i ~/ w;
      colors.fillRange(0, 4, 0);
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          final j = ny * w + nx;
          if (known[j] == 0) continue;
          colors[0] += plate[j * 4];
          colors[1] += plate[j * 4 + 1];
          colors[2] += plate[j * 4 + 2];
          colors[3] += 1;
        }
      }
      for (var c = 0; c < 3; c++) {
        smooth[i * 4 + c] = (colors[c] / colors[3]).round();
      }
    }
    plate.setAll(0, smooth);
    return filled;
  }

  static bool _hasKnownNeighbour(Uint8List known, int x, int y, int w, int h) {
    for (var dy = -1; dy <= 1; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= h) continue;
      for (var dx = -1; dx <= 1; dx++) {
        final nx = x + dx;
        if ((dx == 0 && dy == 0) || nx < 0 || nx >= w) continue;
        if (known[ny * w + nx] == 1) return true;
      }
    }
    return false;
  }
}

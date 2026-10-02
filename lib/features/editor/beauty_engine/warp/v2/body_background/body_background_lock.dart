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

  /// RGBA do fundo limpo no recorte: origem no fundo seguro, preenchido na
  /// faixa de guarda e até `bandPx` por dentro da pessoa, origem no resto.
  final Uint8List plate;

  /// 1 onde a origem já era fundo seguro (fora da borda 0.5 dilatada da
  /// guarda): aí o fundo limpo é a própria origem.
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

  /// O guided filter só decide a ±[trimapRadius] px da borda (nível 0.5 da
  /// máscara): num fundo com textura forte ele copia as arestas da luma e
  /// espalharia alfa pelo fundo, e o fundo com alfa acima de zero é arrastado
  /// com o corpo.
  static const trimapRadius = 1;

  /// Faixa de guarda à volta da borda 0.5: o erro da máscara ampliada é da
  /// ordem de um texel dela, mais o do segmentador.
  static int guardPx(int width, int height, PersonMask mask) {
    final upscale = math.max(width / mask.width, height / mask.height);
    return math.max(
      3,
      math.max((2 * upscale).ceil(), (0.004 * math.max(width, height)).round()),
    );
  }

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
      fields: fields,
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
          out[o + c] =
              (v + lambda * (prepared.plate[p + c] - v)).round().clamp(0, 255);
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
    required List<DisplacementField> fields,
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
    // A máscara do segmentador é confiança suave e ampliada: a rampa dela tem
    // vários px e cobre fundo. A borda é o nível 0.5; daí para fora é fundo.
    final hard = Float32List(n);
    for (var i = 0; i < n; i++) {
      hard[i] = coarse[i] >= 0.5 ? 1 : 0;
    }
    final guided = _guidedFilter(luma, hard, rw, rh, guidedRadius, guidedEps);
    final near = _boxMean(hard, rw, rh, trimapRadius);
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
    // A borda 0.5 erra alguns px: a pessoa que fica fora dela não pode ser
    // fundo conhecido, senão fica parada (fantasma) e semeia o preenchimento.
    final guard = guardPx(width, height, mask);
    final dilated = _boxMean(hard, rw, rh, guard);
    final interior = _boxMean(hard, rw, rh, bandPx);
    final background = Uint8List(n);
    final target = Uint8List(n);
    var filled = 0;
    for (var i = 0; i < n; i++) {
      if (dilated[i] <= 1e-6) {
        background[i] = 1;
      } else if (interior[i] < 1 - 1e-6) {
        target[i] = 1;
        filled++;
      }
    }
    _pullPushFill(plate, background, target, rw, rh);

    // O pull-push só dá a cor média: onde o corpo se mexe, a textura e as
    // arestas do fundo (batente, cortina) vêm de pedaços do fundo real.
    final refine = Uint8List(n);
    var refineCount = 0;
    for (var y = 0; y < rh; y++) {
      final row = (y + top) * width + left;
      for (var x = 0; x < rw; x++) {
        final i = y * rw + x;
        if (target[i] == 0) {
          continue;
        }
        for (final f in fields) {
          if (f.dx[row + x] != 0 || f.dy[row + x] != 0) {
            refine[i] = 1;
            refineCount++;
            break;
          }
        }
      }
    }
    if (refineCount > 0) {
      _patchMatchFill(plate, background, target, refine, rw, rh);
    }

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

  /// Patch 7×7, comparado em 4×4 amostras.
  static const patchRadius = 3;
  static const _patchSteps = [-3, -1, 1, 3];

  /// Janela da busca aleatória: o fundo que serve está perto da borda.
  static const patchSearchRadius = 96;
  static const patchIterations = 3;

  /// Preferência por fontes perto (por px²): com o patch quase só de fundo
  /// inventado, ganha o pedaço de fundo mais próximo.
  static const patchSpatialCost = 0.05;

  /// Inpainting por PatchMatch (Barnes et al.) nos pixels [refine], que já
  /// trazem a cor do pull-push. Cada um copia o centro do patch de fundo
  /// real ([known] no patch inteiro) mais parecido com a sua vizinhança: as
  /// arestas e o grão continuam, em vez da média lisa. Na comparação o fundo
  /// real pesa 1, o inventado 0.5 e o interior da pessoa 0.
  static void _patchMatchFill(
    Uint8List plate,
    Uint8List known,
    Uint8List target,
    Uint8List refine,
    int w,
    int h,
  ) {
    const r = patchRadius;
    if (w <= 2 * r || h <= 2 * r) {
      return;
    }
    final n = w * h;
    final knownF = Float32List(n);
    for (var i = 0; i < n; i++) {
      knownF[i] = known[i].toDouble();
    }
    final full = _boxMean(knownF, w, h, r);
    final valid = Uint8List(n);
    final sources = <int>[];
    for (var y = r; y < h - r; y++) {
      for (var x = r; x < w - r; x++) {
        final i = y * w + x;
        if (full[i] >= 1 - 1e-6) {
          valid[i] = 1;
          sources.add(i);
        }
      }
    }
    if (sources.isEmpty) {
      return;
    }
    final weight = Float32List(n);
    final img = Float32List(n * 3);
    for (var i = 0; i < n; i++) {
      weight[i] = known[i] == 1
          ? 1
          : target[i] == 1
              ? 0.5
              : 0;
      img[i * 3] = plate[i * 4].toDouble();
      img[i * 3 + 1] = plate[i * 4 + 1].toDouble();
      img[i * 3 + 2] = plate[i * 4 + 2].toDouble();
    }
    final pixels = <int>[
      for (var i = 0; i < n; i++)
        if (refine[i] == 1) i,
    ];
    final nnf = Int32List(n)..fillRange(0, n, -1);
    final cost = Float64List(n);
    final random = math.Random(1);

    double distance(int t, int s, double best) {
      final tx = t % w;
      final ty = t ~/ w;
      final sx = s % w;
      final sy = s ~/ w;
      final ddx = (tx - sx).toDouble();
      final ddy = (ty - sy).toDouble();
      var d = patchSpatialCost * (ddx * ddx + ddy * ddy);
      if (d >= best) {
        return d;
      }
      for (final oy in _patchSteps) {
        final ty1 = (ty + oy).clamp(0, h - 1);
        final srow = (sy + oy) * w + sx;
        for (final ox in _patchSteps) {
          final j = ty1 * w + (tx + ox).clamp(0, w - 1);
          final wt = weight[j];
          if (wt == 0) {
            continue;
          }
          final k = (srow + ox) * 3;
          final j3 = j * 3;
          final dr = img[j3] - img[k];
          final dg = img[j3 + 1] - img[k + 1];
          final db = img[j3 + 2] - img[k + 2];
          d += wt * (dr * dr + dg * dg + db * db);
          if (d >= best) {
            return d;
          }
        }
      }
      return d;
    }

    void consider(int t, int s) {
      if (s < 0 || s >= n || valid[s] == 0 || s == nnf[t]) {
        return;
      }
      final d = distance(t, s, cost[t]);
      if (d < cost[t]) {
        cost[t] = d;
        nnf[t] = s;
      }
    }

    int randomAround(int s, int radius) {
      final x =
          (s % w + random.nextInt(2 * radius + 1) - radius).clamp(r, w - 1 - r);
      final y = (s ~/ w + random.nextInt(2 * radius + 1) - radius)
          .clamp(r, h - 1 - r);
      return y * w + x;
    }

    for (final t in pixels) {
      cost[t] = double.infinity;
      for (var k = 0; k < 12; k++) {
        consider(t, randomAround(t, patchSearchRadius));
      }
      if (nnf[t] < 0) {
        final s = sources[random.nextInt(sources.length)];
        nnf[t] = s;
        cost[t] = distance(t, s, double.infinity);
      }
    }

    for (var iteration = 0; iteration < patchIterations; iteration++) {
      for (var pass = 0; pass < 2; pass++) {
        final forward = pass.isEven;
        final step = forward ? 1 : -1;
        for (var p = 0; p < pixels.length; p++) {
          final t = pixels[forward ? p : pixels.length - 1 - p];
          final x = t % w;
          final y = t ~/ w;
          final nx = x - step;
          if (nx >= 0 && nx < w) {
            final s = nnf[t - step];
            if (s >= 0 && refine[t - step] == 1) {
              final sx = s % w + step;
              if (sx >= 0 && sx < w) {
                consider(t, s + step);
              }
            }
          }
          final ny = y - step;
          if (ny >= 0 && ny < h) {
            final s = nnf[t - step * w];
            if (s >= 0 && refine[t - step * w] == 1) {
              consider(t, s + step * w);
            }
          }
          for (var radius = patchSearchRadius; radius >= 1; radius >>= 1) {
            consider(t, randomAround(nnf[t], radius));
          }
        }
      }
      for (final t in pixels) {
        final s = nnf[t] * 3;
        img[t * 3] = img[s];
        img[t * 3 + 1] = img[s + 1];
        img[t * 3 + 2] = img[s + 2];
      }
      if (iteration < patchIterations - 1) {
        for (final t in pixels) {
          cost[t] = distance(t, nnf[t], double.infinity);
        }
      }
    }

    for (final t in pixels) {
      for (var c = 0; c < 3; c++) {
        plate[t * 4 + c] = img[t * 3 + c].round().clamp(0, 255);
      }
    }
  }

  /// Preenche [target] a partir de [known] por pull-push: pirâmide de médias
  /// ponderadas dos conhecidos, depois subida bilinear. Sai liso; a média anel
  /// a anel arrastava raios de cor da borda para dentro do buraco.
  static void _pullPushFill(
    Uint8List plate,
    Uint8List known,
    Uint8List target,
    int w,
    int h,
  ) {
    final n = w * h;
    final c0 = Float32List(n * 3);
    final w0 = Float32List(n);
    var any = false;
    for (var i = 0; i < n; i++) {
      if (known[i] == 1) {
        any = true;
        w0[i] = 1;
        for (var c = 0; c < 3; c++) {
          c0[i * 3 + c] = plate[i * 4 + c].toDouble();
        }
      }
    }
    if (!any) {
      return;
    }
    final colors = <Float32List>[c0];
    final weights = <Float32List>[w0];
    final widths = <int>[w];
    final heights = <int>[h];
    while (widths.last > 1 || heights.last > 1) {
      final pw = widths.last;
      final ph = heights.last;
      final nw = (pw + 1) >> 1;
      final nh = (ph + 1) >> 1;
      final pc = colors.last;
      final pwt = weights.last;
      final nc = Float32List(nw * nh * 3);
      final nwt = Float32List(nw * nh);
      for (var y = 0; y < nh; y++) {
        for (var x = 0; x < nw; x++) {
          var sw = 0.0;
          var s0 = 0.0;
          var s1 = 0.0;
          var s2 = 0.0;
          for (var dy = 0; dy < 2; dy++) {
            final sy = 2 * y + dy;
            if (sy >= ph) continue;
            for (var dx = 0; dx < 2; dx++) {
              final sx = 2 * x + dx;
              if (sx >= pw) continue;
              final j = sy * pw + sx;
              final wt = pwt[j];
              if (wt <= 0) continue;
              sw += wt;
              s0 += pc[j * 3] * wt;
              s1 += pc[j * 3 + 1] * wt;
              s2 += pc[j * 3 + 2] * wt;
            }
          }
          if (sw > 0) {
            final k = y * nw + x;
            nc[k * 3] = s0 / sw;
            nc[k * 3 + 1] = s1 / sw;
            nc[k * 3 + 2] = s2 / sw;
            nwt[k] = math.min(1.0, sw);
          }
        }
      }
      colors.add(nc);
      weights.add(nwt);
      widths.add(nw);
      heights.add(nh);
    }
    for (var l = colors.length - 2; l >= 0; l--) {
      final lw = widths[l];
      final lh = heights[l];
      final c = colors[l];
      final wt = weights[l];
      final uc = colors[l + 1];
      final uw = widths[l + 1];
      final uh = heights[l + 1];
      for (var y = 0; y < lh; y++) {
        final fy = ((y + 0.5) / 2 - 0.5).clamp(0.0, uh - 1.0);
        final y0 = fy.floor();
        final y1 = math.min(uh - 1, y0 + 1);
        final ty = fy - y0;
        for (var x = 0; x < lw; x++) {
          final k = y * lw + x;
          final own = wt[k];
          if (own >= 1) continue;
          final fx = ((x + 0.5) / 2 - 0.5).clamp(0.0, uw - 1.0);
          final x0 = fx.floor();
          final x1 = math.min(uw - 1, x0 + 1);
          final tx = fx - x0;
          for (var ch = 0; ch < 3; ch++) {
            final a = uc[(y0 * uw + x0) * 3 + ch];
            final b = uc[(y0 * uw + x1) * 3 + ch];
            final d = uc[(y1 * uw + x0) * 3 + ch];
            final e = uc[(y1 * uw + x1) * 3 + ch];
            final up = (a + (b - a) * tx) +
                ((d + (e - d) * tx) - (a + (b - a) * tx)) * ty;
            c[k * 3 + ch] = own * c[k * 3 + ch] + (1 - own) * up;
          }
          wt[k] = 1;
        }
      }
    }
    for (var i = 0; i < n; i++) {
      if (target[i] == 0) continue;
      for (var ch = 0; ch < 3; ch++) {
        plate[i * 4 + ch] = c0[i * 3 + ch].round().clamp(0, 255);
      }
    }
  }
}

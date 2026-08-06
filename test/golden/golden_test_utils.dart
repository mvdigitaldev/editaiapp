import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/quality/image_quality_metrics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Tolerâncias de regressão visual (cap. 11 do plano do SDK facial).
///
/// Os defaults valem para render CPU determinístico no CI. Backends GPU
/// (Metal/GLES) têm diferenças de precisão legítimas — use tolerâncias
/// relaxadas por backend quando o device-lab entrar (Sprint 6).
class GoldenTolerance {
  const GoldenTolerance({
    this.minSsim = 0.98,
    this.minPsnr = 35.0,
    this.maxDeltaE2000 = 1.5,
  });

  final double minSsim;
  final double minPsnr;
  final double maxDeltaE2000;

  /// Render determinístico byte-a-byte (mesmo código, mesma plataforma).
  static const strict = GoldenTolerance(
    minSsim: 0.995,
    minPsnr: 45.0,
    maxDeltaE2000: 0.5,
  );
}

/// Compara um resultado RGBA com o golden aprovado em
/// `test/golden/goldens/<name>.png`.
///
/// - Golden ausente: falha pedindo geração, a menos que a env
///   `UPDATE_GOLDENS=1` esteja setada — aí grava e passa.
/// - `UPDATE_GOLDENS=1` também regrava goldens existentes (aprovação de
///   mudança intencional). Revise o diff da imagem no git antes de commitar.
void expectMatchesGolden({
  required String name,
  required Uint8List rgba,
  required int width,
  required int height,
  GoldenTolerance tolerance = const GoldenTolerance(),
}) {
  final goldenFile = File('test/golden/goldens/$name.png');
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';

  if (update || !goldenFile.existsSync()) {
    if (!update && !goldenFile.existsSync()) {
      fail(
        'Golden ausente: ${goldenFile.path}\n'
        'Gere com: UPDATE_GOLDENS=1 flutter test test/golden',
      );
    }
    goldenFile.parent.createSync(recursive: true);
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    goldenFile.writeAsBytesSync(img.encodePng(image));
    // ignore: avoid_print
    print('golden atualizado: ${goldenFile.path}');
    return;
  }

  final golden = img.decodePng(goldenFile.readAsBytesSync());
  if (golden == null) {
    fail('Golden corrompido: ${goldenFile.path}');
  }
  expect(golden.width, width,
      reason: 'largura difere do golden $name — mudança de resolução?');
  expect(golden.height, height,
      reason: 'altura difere do golden $name — mudança de resolução?');

  final goldenRgba = Uint8List(width * height * 4);
  var offset = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = golden.getPixel(x, y);
      goldenRgba[offset++] = pixel.r.toInt();
      goldenRgba[offset++] = pixel.g.toInt();
      goldenRgba[offset++] = pixel.b.toInt();
      goldenRgba[offset++] = pixel.a.toInt();
    }
  }

  final ssim = ImageQualityMetrics.ssim(
    goldenRgba,
    rgba,
    width: width,
    height: height,
  );
  final psnr = ImageQualityMetrics.psnr(goldenRgba, rgba);
  final deltaE = ImageQualityMetrics.deltaE2000Mean(goldenRgba, rgba);

  final summary = 'golden=$name ssim=${ssim.toStringAsFixed(4)} '
      'psnr=${psnr.toStringAsFixed(1)}dB '
      'dE2000=${deltaE.toStringAsFixed(2)}';

  expect(ssim, greaterThanOrEqualTo(tolerance.minSsim), reason: summary);
  expect(psnr, greaterThanOrEqualTo(tolerance.minPsnr), reason: summary);
  expect(deltaE, lessThanOrEqualTo(tolerance.maxDeltaE2000), reason: summary);
}

/// Entrada do corpus de fotos reais (test/golden/corpus/).
class CorpusEntry {
  const CorpusEntry({
    required this.id,
    required this.file,
    required this.tags,
  });

  final String id;
  final File file;
  final Map<String, dynamic> tags;
}

/// Carrega o manifesto do corpus. Fotos ausentes são ignoradas (o corpus com
/// pessoas reais não é commitado — ver test/golden/corpus/README.md), então
/// os testes de corpus rodam apenas nas máquinas que possuem as fotos.
List<CorpusEntry> loadCorpusEntries() {
  final manifest = File('test/golden/corpus/manifest.json');
  if (!manifest.existsSync()) return const [];
  final data = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
  final entries = <CorpusEntry>[];
  for (final item in (data['photos'] as List<dynamic>? ?? const [])) {
    final map = item as Map<String, dynamic>;
    final file = File('test/golden/corpus/${map['file']}');
    if (!file.existsSync()) continue;
    entries.add(CorpusEntry(
      id: map['id'] as String,
      file: file,
      tags: map,
    ));
  }
  return entries;
}

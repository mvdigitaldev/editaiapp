import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../filters/body/mvp_benchmark_bodies.dart';

const _dumpRoot = '.cursor/body-reshape-v2/catalog';

void main() {
  late List<BodyBenchmarkPhoto> photos;

  setUpAll(() {
    photos = loadAvailableRealBenchmarkBodies();
  });

  test('o catálogo de corpo tem as quatro fotos reais', () {
    expect(photos.map((p) => p.id), [
      'body-p01',
      'body-p02',
      'body-p03',
      'body-p04',
    ]);
    expect(photos.map((p) => p.dumpId), ['p01', 'p02', 'p03', 'p04']);
    expect(photos.where((p) => p.sex == 'female').length, 3);
    expect(photos.where((p) => p.sex == 'male').length, 1);
    expect(photos.where((p) => p.framing == 'full').length, 1);
  });

  test('cada foto decodifica no tamanho do manifesto', () {
    const expected = {
      'body-p01': (640, 800),
      'body-p02': (665, 1024),
      'body-p03': (682, 1024),
      'body-p04': (682, 1024),
    };
    for (final photo in photos) {
      final size = expected[photo.id]!;
      expect(photo.width, size.$1, reason: photo.id);
      expect(photo.height, size.$2, reason: photo.id);
      expect(photo.rgba.length, photo.width * photo.height * 4, reason: photo.id);
    }
  });

  test('seed do laboratório grava original.png em .cursor/body-reshape-v2/catalog',
      () {
    Directory(_dumpRoot).createSync(recursive: true);
    final summary = <Map<String, Object?>>[];
    for (final photo in photos) {
      final dir = Directory('$_dumpRoot/${photo.dumpId}');
      dir.createSync(recursive: true);
      _saveRgba(
        '${dir.path}/original.png',
        photo.rgba,
        photo.width,
        photo.height,
      );
      File('${dir.path}/meta.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'id': photo.id,
          'dumpId': photo.dumpId,
          'label': photo.label,
          'image': photo.imagePath,
          'width': photo.width,
          'height': photo.height,
          'sex': photo.sex,
          'framing': photo.framing,
          'notes': photo.notes,
          'hasPose': photo.hasPose,
        }),
      );
      summary.add({
        'id': photo.id,
        'dumpId': photo.dumpId,
        'label': photo.label,
        'width': photo.width,
        'height': photo.height,
        'sex': photo.sex,
        'framing': photo.framing,
        'hasPose': photo.hasPose,
        'original': '${dir.path}/original.png',
      });
    }
    File('$_dumpRoot/summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'lab': 'body-reshape-v2/catalog',
        'count': summary.length,
        'photos': summary,
      }),
    );
    expect(File('$_dumpRoot/summary.json').existsSync(), isTrue);
    for (final photo in photos) {
      expect(
        File('$_dumpRoot/${photo.dumpId}/original.png').existsSync(),
        isTrue,
        reason: photo.id,
      );
    }
  });
}

void _saveRgba(String path, List<int> rgba, int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  var o = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3]);
      o += 4;
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

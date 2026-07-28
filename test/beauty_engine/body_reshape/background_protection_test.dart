import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/matte_preprocessor.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/protection_maps.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/protection/background_protector.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/protection/edge_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/protection/line_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/models/control_point.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(120, 160);
  const protector = BackgroundProtector();

  group('EdgeMap / LineMap', () {
    test('detects strong vertical line in synthetic luminance', () {
      final luma = _flatLuma(imageSize, 0.2);
      // Linha vertical forte em x=20.
      for (var y = 10; y < 150; y++) {
        luma[y * 120 + 19] = 0.0;
        luma[y * 120 + 20] = 1.0;
        luma[y * 120 + 21] = 1.0;
        luma[y * 120 + 22] = 0.0;
      }

      final edges = const EdgeMapBuilder().buildFromLuminance(
        luminance: luma,
        width: 120,
        height: 160,
        imageSize: imageSize,
      );
      final lines = const LineMapBuilder().build(edges);

      final edgeAtLine = math.max(
        edges.sampleMagnitude(20 / 119, 0.5),
        edges.sampleAtPixel(20, 80),
      );
      expect(edgeAtLine, greaterThan(0.15));
      expect(lines.hasLines, isTrue);
      expect(
        math.max(
          lines.sampleStrength(20 / 119, 0.5),
          lines.sampleAtPixel(20, 80),
        ),
        greaterThan(0.1),
      );
    });
  });

  group('RigidityMap / BackgroundProtector', () {
    test('far background is rigid; person interior is soft', () {
      final matte = _centerPersonMatte(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        matte,
        imageSize: imageSize,
      );
      final luma = _flatLuma(imageSize, 0.35);
      // Linha no fundo (fora da pessoa).
      for (var y = 5; y < 155; y++) {
        luma[y * 120 + 8] = 1.0;
        luma[y * 120 + 9] = 0.0;
      }

      final result = protector.analyzeLuminance(
        luminance: luma,
        width: 120,
        height: 160,
        imageSize: imageSize,
        protection: protection,
      );

      final farBg = result.rigidity.sampleNormalized(0.05, 0.5);
      final personCore = result.rigidity.sampleNormalized(0.5, 0.5);
      expect(farBg, greaterThan(0.4));
      expect(personCore, lessThan(0.08));
    });

    test('absence of lines does not freeze body deformation', () {
      final matte = _centerPersonMatte(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        matte,
        imageSize: imageSize,
      );
      // Fundo uniforme sem linhas.
      final luma = _flatLuma(imageSize, 0.4);
      final result = protector.analyzeLuminance(
        luminance: luma,
        width: 120,
        height: 160,
        imageSize: imageSize,
        protection: protection,
      );

      expect(result.lines.hasLines, isFalse);
      expect(result.rigidity.sampleNormalized(0.5, 0.5), lessThan(0.08));

      final field = _syntheticBodyField(imageSize, protection);
      final centerIdx = (field.gridHeight ~/ 2) * field.gridWidth +
          (field.gridWidth ~/ 2);
      // Garante deslocamento corporal conhecido antes da proteção.
      field.displacement[centerIdx * 2] = 6;
      field.displacement[centerIdx * 2 + 1] = 0;
      field.mask[centerIdx] = 1;

      final protected = protector.applyToField(
        field: field,
        rigidity: result.rigidity,
        lines: result.lines,
      );

      final mag = math.sqrt(
        protected.displacement[centerIdx * 2] *
                protected.displacement[centerIdx * 2] +
            protected.displacement[centerIdx * 2 + 1] *
                protected.displacement[centerIdx * 2 + 1],
      );
      expect(mag, greaterThan(4.0));
      expect(protected.isIdentity, isFalse);
    });

    test('structural lines stay within distortion budget', () {
      final matte = _centerPersonMatte(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        matte,
        imageSize: imageSize,
      );
      final luma = _flatLuma(imageSize, 0.25);
      for (var y = 5; y < 155; y++) {
        luma[y * 120 + 10] = 1.0;
        luma[y * 120 + 11] = 0.0;
      }

      final result = protector.analyzeLuminance(
        luminance: luma,
        width: 120,
        height: 160,
        imageSize: imageSize,
        protection: protection,
      );

      // Campo artificial com deslocamento grande no fundo.
      final raw = WarpField(
        gridWidth: 25,
        gridHeight: 33,
        displacement: Float32List(25 * 33 * 2),
        mask: Float32List(25 * 33),
        imageSize: imageSize,
        region: MeshRegion.torso,
        controlPoints: const [
          ControlPoint(source: Offset(10, 80), target: Offset(25, 80)),
        ],
        intensity: 1,
      );
      for (var i = 0; i < raw.mask.length; i++) {
        raw.mask[i] = 1;
        raw.displacement[i * 2] = 12; // deslocamento absurdo
        raw.displacement[i * 2 + 1] = 0;
      }

      final protected = protector.applyToField(
        field: raw,
        rigidity: result.rigidity,
        lines: result.lines,
      );

      // Amostra perto da linha vertical (x≈10).
      final gx = ((10 / imageSize.width) * (25 - 1)).round();
      final gy = 16;
      final idx = gy * 25 + gx;
      final dx = protected.displacement[idx * 2].abs();
      expect(dx, lessThanOrEqualTo(protector.maxLineDistortionPx + 0.05));
    });

    test('far background displacement becomes immobile', () {
      final matte = _centerPersonMatte(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        matte,
        imageSize: imageSize,
      );
      final luma = _flatLuma(imageSize, 0.3);
      final result = protector.analyzeLuminance(
        luminance: luma,
        width: 120,
        height: 160,
        imageSize: imageSize,
        protection: protection,
      );

      final field = _syntheticBodyField(imageSize, protection);
      // Força deslocamento também no canto.
      field.displacement[0] = 8;
      field.displacement[1] = 0;
      field.mask[0] = 1;

      final protected = protector.applyToField(
        field: field,
        rigidity: result.rigidity,
        lines: result.lines,
      );

      expect(protected.displacement[0].abs(), lessThan(1.0));
      expect(protected.rigidityMap, isNotNull);
    });
  });

  group('BodyFilterPipeline background protection', () {
    test('analyzeBackground + applyBackgroundProtection wire together', () {
      const pipeline = BodyFilterPipeline();
      final matte = _centerPersonMatte(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        matte,
        imageSize: imageSize,
      );
      final luma = _flatLuma(imageSize, 0.35);
      for (var y = 0; y < 160; y++) {
        luma[y * 120 + 6] = 1.0;
      }

      final analysis = pipeline.analyzeBackground(
        imageSize: imageSize,
        protection: protection,
        luminance: luma,
        width: 120,
        height: 160,
      );
      final field = _syntheticBodyField(imageSize, protection);
      final protected = pipeline.applyBackgroundProtection(
        field: field,
        backgroundProtection: analysis,
      );

      expect(protected.rigidityMap, isNotNull);
      expect(analysis.analysis.isEmpty, isFalse);
    });
  });
}

Float32List _flatLuma(Size size, double value) {
  final w = size.width.round();
  final h = size.height.round();
  return Float32List.fromList(List.filled(w * h, value));
}

PersonMatte _centerPersonMatte(Size size) {
  final w = size.width.round();
  final h = size.height.round();
  final alpha = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final nx = x / (w - 1);
      final ny = y / (h - 1);
      final inside = nx >= 0.32 && nx <= 0.68 && ny >= 0.22 && ny <= 0.82;
      alpha[y * w + x] = inside ? 255 : 0;
    }
  }
  return PersonMatte(
    alpha: alpha,
    width: w,
    height: h,
    providerId: 'test',
  );
}

WarpField _syntheticBodyField(Size imageSize, ProtectionMaps protection) {
  return const WarpFieldBuilder(
    gridWidth: 25,
    gridHeight: 33,
    maskFeatherPx: 40,
  ).build(
    controlPoints: const [
      ControlPoint(source: Offset(45, 80), target: Offset(55, 80)),
      ControlPoint(source: Offset(75, 80), target: Offset(65, 80)),
      ControlPoint(source: Offset(60, 50), target: Offset(60, 50)),
      ControlPoint(source: Offset(60, 110), target: Offset(60, 110)),
    ],
    imageSize: imageSize,
    region: MeshRegion.torso,
    intensity: 0.85,
    protectionMaps: protection,
  );
}

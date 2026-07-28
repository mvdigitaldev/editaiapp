import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/texture_confidence_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/background_correction_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/body_multi_pass_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/pass_profiler.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/texture_stabilization_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/tps_refinement_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/protection/rigidity_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/models/control_point.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(64, 64);

  group('TextureConfidenceMap', () {
    test('assigns higher confidence to patterned regions than flat', () {
      final rgba = _checkerboardRgba(64, 64, cell: 4);
      final map = TextureConfidenceMap.fromRgba(
        rgba: rgba,
        width: 64,
        height: 64,
        imageSize: imageSize,
        downsample: 1,
      );

      expect(map.isEmpty, isFalse);
      expect(map.maxValue, greaterThan(0.2));
      expect(map.meanValue, greaterThan(0.05));

      final flat = TextureConfidenceMap.fromRgba(
        rgba: _solidRgba(64, 64, 120, 120, 120),
        width: 64,
        height: 64,
        imageSize: imageSize,
        downsample: 1,
      );
      expect(flat.meanValue, lessThan(map.meanValue));
    });
  });

  group('TpsRefinementPass', () {
    test('reduces high-frequency displacement energy within intensity limit', () {
      final field = _noisyField(imageSize);
      final beforeEnergy = _displacementEnergy(field);
      final refined = const TpsRefinementPass(lowPassBlend: 0.7).refine(
        field: field,
      );
      final afterEnergy = _displacementEnergy(refined);

      expect(refined.isIdentity, isFalse);
      expect(afterEnergy, lessThan(beforeEnergy));
      // Não anula o efeito: energia permanece significativa.
      expect(afterEnergy, greaterThan(beforeEnergy * 0.2));
    });
  });

  group('TextureStabilizationPass', () {
    test('attenuates stretch on high-confidence texture within floor', () {
      final field = _highStretchField(imageSize);
      final confidence = TextureConfidenceMap.filled(
        width: 8,
        height: 8,
        imageSize: imageSize,
        value: 0.9,
      );
      final result = const TextureStabilizationPass(
        stretchThreshold: 1.1,
        maxAttenuation: 0.5,
        preserveBodyFloor: 0.4,
      ).stabilize(field: field, confidence: confidence);

      expect(result.attenuatedCells, greaterThan(0));
      final mid = (4 * 8 + 4) * 2;
      final originalMag = math.sqrt(
        field.displacement[mid] * field.displacement[mid] +
            field.displacement[mid + 1] * field.displacement[mid + 1],
      );
      final newMag = math.sqrt(
        result.field.displacement[mid] * result.field.displacement[mid] +
            result.field.displacement[mid + 1] *
                result.field.displacement[mid + 1],
      );
      expect(newMag, lessThan(originalMag));
      expect(newMag, greaterThanOrEqualTo(originalMag * 0.39));
    });
  });

  group('BackgroundCorrectionPass', () {
    test('does not bend rigid lines (zero disp where rigidity high)', () {
      final rigidity = RigidityMap(
        values: Float32List.fromList([
          for (var i = 0; i < 64; i++) i % 8 == 3 ? 1.0 : 0.0,
        ]),
        width: 8,
        height: 8,
        imageSize: imageSize,
        maxValue: 1,
        hadLines: true,
      );
      final field = _uniformField(imageSize, dx: 8, dy: 0).copyWith(
        rigidityMap: rigidity,
      );

      final result = const BackgroundCorrectionPass().correct(
        field: field,
        rigidity: rigidity,
      );

      // Coluna x=3 (rigidez 1) deve ficar imóvel.
      for (var gy = 0; gy < 8; gy++) {
        final idx = gy * 8 + 3;
        expect(result.field.displacement[idx * 2].abs(), lessThan(1e-6));
        expect(result.field.mask[idx], 0);
      }
      expect(result.rigidCellsProtected, greaterThan(0));
    });

    test('softens matte-edge mask to reduce ghosting band', () {
      final field = _edgeMaskField(imageSize);
      final result = const BackgroundCorrectionPass(ghostFeather: 0.2).correct(
        field: field,
      );
      // Célula com máscara intermediária deve ser atenuada.
      expect(result.correctedCells, greaterThan(0));
      expect(result.field.mask[3], lessThan(field.mask[3]));
    });
  });

  group('WarpCpuRemap Sprint 11', () {
    test('anti-ghosting keeps corner pixels unchanged under edge mask', () {
      final rgba = _checkerboardRgba(32, 32, cell: 4);
      final field = WarpField(
        gridWidth: 8,
        gridHeight: 8,
        displacement: Float32List(8 * 8 * 2)..fillRange(0, 8 * 8 * 2, 0),
        mask: Float32List(8 * 8),
        imageSize: const Size(32, 32),
        region: MeshRegion.torso,
        controlPoints: const [
          ControlPoint(source: Offset(16, 16), target: Offset(20, 16)),
        ],
        intensity: 1,
      );
      // Só centro ativo com deslocamento.
      for (var gy = 3; gy <= 5; gy++) {
        for (var gx = 3; gx <= 5; gx++) {
          final idx = gy * 8 + gx;
          field.mask[idx] = 0.5;
          field.displacement[idx * 2] = 6;
        }
      }

      final out = const WarpCpuRemap(antiGhosting: true).apply(
        rgba: rgba,
        width: 32,
        height: 32,
        field: field,
      );

      // Canto fora da ROI permanece idêntico (sem ghost).
      expect(out[0], rgba[0]);
      expect(out[1], rgba[1]);
      expect(out[2], rgba[2]);
    });

    test('rigidity map blocks warp on structural background', () {
      final rgba = _solidRgba(16, 16, 10, 20, 30);
      // Pinta um pixel distinto à direita para detectar pull.
      rgba[(8 * 16 + 12) * 4] = 200;
      final rigidity = RigidityMap(
        values: Float32List.fromList(List.filled(16, 1.0)),
        width: 4,
        height: 4,
        imageSize: const Size(16, 16),
        maxValue: 1,
        hadLines: true,
      );
      final field = _uniformField(const Size(16, 16), dx: 4, dy: 0).copyWith(
        rigidityMap: rigidity,
      );

      final out = WarpCpuRemap(antiGhosting: true, rigidityMap: rigidity).apply(
        rgba: rgba,
        width: 16,
        height: 16,
        field: field,
      );
      // Com rigidity total, saída ≈ original.
      expect(out[0], rgba[0]);
      expect(out[1], rgba[1]);
      expect(out[2], rgba[2]);
    });
  });

  group('BodyMultiPassPipeline Sprint 11 toggles', () {
    test('runs texture and background passes when enabled', () {
      final seed = _noisyField(imageSize);
      final pipeline = BodyMultiPassPipeline();
      final result = pipeline.run(
        BodyMultiPassInput(
          imageSize: imageSize,
          config: const BodyMultiPassConfig(
            tpsRefinement: true,
            textureStabilization: true,
            backgroundCorrection: true,
          ),
          seedField: seed,
          textureConfidence: TextureConfidenceMap.filled(
            width: 8,
            height: 8,
            imageSize: imageSize,
            value: 0.8,
          ),
        ),
      );

      expect(
        result.executedPasses,
        ['tps_refinement', 'texture_stabilization', 'background_correction'],
      );
      expect(result.field.isIdentity, isFalse);
    });
  });
}

double _displacementEnergy(WarpField field) {
  var e = 0.0;
  for (var i = 0; i < field.displacement.length; i += 2) {
    final dx = field.displacement[i];
    final dy = field.displacement[i + 1];
    final m = field.mask[i ~/ 2];
    e += (dx * dx + dy * dy) * m;
  }
  return e;
}

WarpField _noisyField(Size imageSize) {
  const gw = 16;
  const gh = 16;
  final disp = Float32List(gw * gh * 2);
  final mask = Float32List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      final idx = gy * gw + gx;
      mask[idx] = 1;
      // Baixa frequência + ruído.
      disp[idx * 2] = 4 + ((gx + gy).isEven ? 3.0 : -3.0);
      disp[idx * 2 + 1] = (gx.isEven ? 1.5 : -1.5);
    }
  }
  return WarpField(
    gridWidth: gw,
    gridHeight: gh,
    displacement: disp,
    mask: mask,
    imageSize: imageSize,
    region: MeshRegion.torso,
    controlPoints: const [
      ControlPoint(source: Offset(32, 32), target: Offset(36, 32)),
    ],
    intensity: 1,
  );
}

WarpField _highStretchField(Size imageSize) {
  const gw = 8;
  const gh = 8;
  final disp = Float32List(gw * gh * 2);
  final mask = Float32List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      final idx = gy * gw + gx;
      mask[idx] = 1;
      // Gradiente forte → stretch alto.
      disp[idx * 2] = gx * 6.0;
    }
  }
  return WarpField(
    gridWidth: gw,
    gridHeight: gh,
    displacement: disp,
    mask: mask,
    imageSize: imageSize,
    region: MeshRegion.torso,
    controlPoints: const [
      ControlPoint(source: Offset(0.5, 0.5), target: Offset(0.7, 0.5)),
    ],
    intensity: 1,
  );
}

WarpField _uniformField(Size imageSize, {required double dx, double dy = 0}) {
  const gw = 8;
  const gh = 8;
  final disp = Float32List(gw * gh * 2);
  final mask = Float32List(gw * gh);
  for (var i = 0; i < gw * gh; i++) {
    disp[i * 2] = dx;
    disp[i * 2 + 1] = dy;
    mask[i] = 1;
  }
  return WarpField(
    gridWidth: gw,
    gridHeight: gh,
    displacement: disp,
    mask: mask,
    imageSize: imageSize,
    region: MeshRegion.torso,
    controlPoints: const [
      ControlPoint(source: Offset(0.5, 0.5), target: Offset(0.6, 0.5)),
    ],
    intensity: 1,
  );
}

WarpField _edgeMaskField(Size imageSize) {
  const gw = 8;
  const gh = 8;
  final disp = Float32List(gw * gh * 2);
  final mask = Float32List(gw * gh);
  for (var i = 0; i < gw * gh; i++) {
    disp[i * 2] = 5;
    mask[i] = 0.45; // faixa intermediária → ghost candidate
  }
  return WarpField(
    gridWidth: gw,
    gridHeight: gh,
    displacement: disp,
    mask: mask,
    imageSize: imageSize,
    region: MeshRegion.torso,
    controlPoints: const [
      ControlPoint(source: Offset(0.5, 0.5), target: Offset(0.55, 0.5)),
    ],
    intensity: 1,
  );
}

Uint8List _solidRgba(int width, int height, int r, int g, int b) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    bytes[o] = r;
    bytes[o + 1] = g;
    bytes[o + 2] = b;
    bytes[o + 3] = 255;
  }
  return bytes;
}

Uint8List _checkerboardRgba(int width, int height, {required int cell}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final on = ((x ~/ cell) + (y ~/ cell)).isEven;
      final o = (y * width + x) * 4;
      final v = on ? 220 : 40;
      bytes[o] = v;
      bytes[o + 1] = v;
      bytes[o + 2] = v;
      bytes[o + 3] = 255;
    }
  }
  return bytes;
}

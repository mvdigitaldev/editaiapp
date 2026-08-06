import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/brush/brush_warp_field_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/anti_folding_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:flutter_test/flutter_test.dart';

/// Garante que o campo entregue ao shader nunca dobra (sem redemoinho) e que
/// o pincel sozinho produz um campo aplicável.
void main() {
  const imageSize = Size(800, 1400);
  const folding = AntiFoldingPass();

  int foldsIn(WarpField f) => folding.countInversions(
        displacement: f.displacement,
        mask: f.mask,
        gridWidth: f.gridWidth,
        gridHeight: f.gridHeight,
        imageSize: f.imageSize,
      );

  test('anti-folding guard removes extreme compression, not just inversion',
      () {
    // Campo com salto brusco: metade puxa forte para a esquerda, metade zero.
    const gw = 32;
    const gh = 32;
    final disp = Float32List(gw * gh * 2);
    final mask = Float32List(gw * gh);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final i = gy * gw + gx;
        mask[i] = 1;
        disp[i * 2] = gx < gw ~/ 2 ? 0.0 : -90.0;
      }
    }
    final folded = WarpField(
      gridWidth: gw,
      gridHeight: gh,
      displacement: disp,
      mask: mask,
      imageSize: imageSize,
      region: MeshRegion.torso,
      intensity: 1,
    );

    expect(foldsIn(folded), greaterThan(0));
    final fixed = folding.resolve(folded).field;
    expect(foldsIn(fixed), 0);
  });

  test('brush stroke alone yields non-identity field that survives the guard',
      () {
    const builder = BrushWarpFieldBuilder();
    final field = builder.build(
      strokes: [
        const WarpStroke(
          points: [Offset(0.66, 0.36), Offset(0.60, 0.36)],
          radiusNormalized: 0.08,
          strength: 0.8,
        ),
      ],
      imageSize: imageSize,
    );

    expect(field.isIdentity, isFalse);
    final guarded = folding.resolve(field).field;
    expect(guarded.isIdentity, isFalse);
    expect(foldsIn(guarded), 0);
    expect(guarded.maxDisplacementMagnitude, greaterThan(8));

    // E move pixels de verdade.
    final rgba = _stripes(imageSize);
    final out = const WarpCpuRemap().apply(
      rgba: rgba,
      width: imageSize.width.round(),
      height: imageSize.height.round(),
      field: guarded,
    );
    var changed = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i] != out[i]) changed++;
    }
    expect(changed, greaterThan(500));
  });
}

Uint8List _stripes(Size size) {
  final w = size.width.round();
  final h = size.height.round();
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final v = (x ~/ 8).isEven ? 30 : 220;
      rgba[i] = v;
      rgba[i + 1] = v;
      rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

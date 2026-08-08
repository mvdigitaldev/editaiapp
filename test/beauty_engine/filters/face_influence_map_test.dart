import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_influence_map_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_region.dart';
import 'package:flutter_test/flutter_test.dart';

import 'skin/skin_face_fixture.dart';

void main() {
  test('midFace influence peaks at nose', () {
    final map = FaceInfluenceMapBuilder.build(
      region: FaceWarpRegion.midFace,
      face: syntheticFace(),
      imageSize: const Size(640, 960),
    );
    expect(map.sampleNormalized(0.5, 0.48), greaterThan(0.3));
    expect(map.sampleNormalized(0.1, 0.85), lessThan(0.05));
  });
}

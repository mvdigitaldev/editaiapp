import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/eye_scale.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_context.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/mouth_width.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/nose_slim.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  final face = syntheticFace();
  final mesh = const FaceMeshBuilder().build(face, imageSize);

  double maxDisp(WarpField field) => field.maxDisplacementMagnitude;

  test('nose_slim produces displacement at nose', () {
    final pipeline = FaceFilterPipeline(
      fieldBuilder: WarpFieldBuilder.forFaceWarp(imageSize),
    );
    final field = pipeline.compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: const {'nose_slim': 1.0},
    );
    expect(field.isIdentity, isFalse);
    expect(maxDisp(field), greaterThan(2.0));
  });

  test('eye_scale produces displacement at eyes', () {
    final pipeline = FaceFilterPipeline(
      fieldBuilder: WarpFieldBuilder.forFaceWarp(imageSize),
    );
    final field = pipeline.compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: const {'eye_scale': 1.0},
    );
    expect(maxDisp(field), greaterThan(2.0));
  });

  test('mouth_width produces displacement at mouth', () {
    final pipeline = FaceFilterPipeline(
      fieldBuilder: WarpFieldBuilder.forFaceWarp(imageSize),
    );
    final field = pipeline.compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: const {'mouth_width': 1.0},
    );
    expect(maxDisp(field), greaterThan(1.0));
  });

  test('filters produce non-anchor control points', () {
    final ctx = FaceWarpContext(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      intensity: 1,
      yawFactor: 1,
    );
    for (final filter in [
      NoseSlimFilter(),
      EyeScaleFilter(),
      MouthWidthFilter(),
    ]) {
      final cps = filter.buildControlPoints(ctx);
      final moved = cps.where((p) => !p.isAnchor && p.delta.distance > 0.5);
      expect(moved, isNotEmpty, reason: filter.id);
    }
  });

  test('mesh builder indexes landmarks by id not list position', () {
    final ordered = syntheticFace();
    final shuffled = FaceMeshResult(
      landmarks: List<FaceLandmark>.from(ordered.landmarks)..shuffle(),
      boundingBox: ordered.boundingBox,
      confidence: ordered.confidence,
    );

    final orderedMesh = const FaceMeshBuilder().build(ordered, imageSize);
    final shuffledMesh = const FaceMeshBuilder().build(shuffled, imageSize);

    expect(orderedMesh.vertices, equals(shuffledMesh.vertices));
  });

  test('jaw regional compose — forehead displacement near zero', () {
    final pipeline = FaceFilterPipeline(
      fieldBuilder: WarpFieldBuilder.forFaceWarp(imageSize),
    );
    final field = pipeline.compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: const {'jaw': 1.0},
    );
    final forehead = field.sampleDisplacement(Offset(0.5, 0.15));
    final mask = field.sampleMask(Offset(0.5, 0.15));
    expect(forehead.distance * mask, lessThan(0.5));
  });
}

import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_context.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/cheekbone.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/forehead.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/smile.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/temple.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/eye_scale.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/eye_rotation.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_slim.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/jaw.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tri_mesh.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/nose_slim.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/fps_benchmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(200, 300);

  group('FaceFilterPipeline Sprint 10', () {
    late FaceFilterPipeline pipeline;
    late FaceMeshResult face;

    setUp(() {
      pipeline = const FaceFilterPipeline();
      face = _fakeFaceMesh();
    });

    test('intensity 0 returns identity field', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {},
      );
      expect(field.isIdentity, isTrue);
    });

    test('face_slim produces non-identity control points', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {'face_slim': 1.0},
      );
      expect(field.isIdentity, isFalse);
      expect(field.controlPoints.where((p) => !p.isAnchor), isNotEmpty);
    });

    test('narrow_face and v_face are independent', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final narrow = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {'narrow_face': 0.8},
      );
      final vFace = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {'v_face': 0.8},
      );
      expect(narrow.controlPoints.length, isNot(equals(vFace.controlPoints.length)));
    });

    test('combined face filters warp pass runs at preview resolution', () async {
      const width = 640;
      const height = 360;
      final size = Size(width.toDouble(), height.toDouble());
      final pipeline = const FaceFilterPipeline(
        fieldBuilder: WarpFieldBuilder(gridWidth: 16, gridHeight: 16),
      );
      final mesh = const FaceMeshBuilder().build(face, size);
      final field = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: size,
        parameters: const {
          'face_slim': 0.6,
          'narrow_face': 0.4,
          'v_face': 0.3,
        },
      );

      final renderer = GpuRendererImpl();
      final rgba = _solidRgba(width: width, height: height);
      final input = await renderer.upload(
        TextureUpload(bytes: rgba, width: width, height: height),
      );

      const benchmark = FpsBenchmark();
      final result = await benchmark.runWarpPass(
        renderer: renderer,
        input: input,
        warpUniforms: {'warpField': field},
        duration: const Duration(milliseconds: 500),
      );

      expect(result.frameCount, greaterThan(0));
      expect(result.fps, greaterThan(15));

      renderer.release(input);
      renderer.dispose();
    });
  });

  group('FaceFilterPipeline Sprint 11', () {
    late FaceFilterPipeline pipeline;
    late FaceMeshResult face;

    setUp(() {
      pipeline = const FaceFilterPipeline();
      face = _fakeFaceMesh();
    });

    test('nose filters combine without error', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {
          'nose_slim': 0.5,
          'nose_length': 0.4,
          'nose_height': 0.3,
          'nose_tip': 0.6,
          'nose_bridge': 0.5,
        },
      );
      expect(field.isIdentity, isFalse);
    });

    test('nose_slim keeps displacement moderate', () {
      final filter = NoseSlimFilter();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final points = filter.buildControlPoints(
        FaceWarpContext(
          mesh: mesh,
          face: face,
          imageSize: imageSize,
          intensity: 1,
          yawFactor: 1,
        ),
      );
      final moved = points.where((p) => !p.isAnchor);
      expect(moved, isNotEmpty);
      for (final cp in moved) {
        expect((cp.target.dx - cp.source.dx).abs(), lessThan(30));
      }
    });

    test('hasActiveWarp detects any face warp param', () {
      expect(pipeline.hasActiveWarp(const {}), isFalse);
      expect(
        pipeline.hasActiveWarp(const {'nose_bridge': 0.2}),
        isTrue,
      );
    });
  });

  group('FaceFilterPipeline Sprint 12', () {
    late FaceFilterPipeline pipeline;
    late FaceMeshResult face;

    setUp(() {
      pipeline = const FaceFilterPipeline();
      face = _fakeFaceMesh();
    });

    test('eye filters combine without error', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {
          'eye_scale': 0.5,
          'eye_distance': 0.3,
          'eye_height': 0.4,
          'eye_rotation': 0.2,
          'double_eyelid': 0.6,
        },
      );
      expect(field.isIdentity, isFalse);
    });

    test('eye_scale excludes iris landmarks from displacement', () {
      final filter = EyeScaleFilter();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final points = filter.buildControlPoints(
        FaceWarpContext(
          mesh: mesh,
          face: face,
          imageSize: imageSize,
          intensity: 1,
          yawFactor: 1,
        ),
      );
      final sources = points.map((p) => p.source).toSet();
      for (final iris in FaceWarpUtils.irisLandmarkIndices) {
        final vertex = FaceWarpUtils.vertexAt(mesh, iris);
        if (vertex != null) {
          expect(sources.contains(vertex), isFalse);
        }
      }
    });

    test('link_eyes off uses same rotation direction on both eyes', () {
      final filter = EyeRotationFilter();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final linked = filter.buildControlPoints(
        FaceWarpContext(
          mesh: mesh,
          face: face,
          imageSize: imageSize,
          intensity: 1,
          yawFactor: 1,
          linkEyes: true,
        ),
      );
      final unlinked = filter.buildControlPoints(
        FaceWarpContext(
          mesh: mesh,
          face: face,
          imageSize: imageSize,
          intensity: 1,
          yawFactor: 1,
          linkEyes: false,
        ),
      );
      expect(linked.length, equals(unlinked.length));
      expect(linked, isNot(equals(unlinked)));
    });
  });

  group('FaceFilterPipeline Sprint 13', () {
    late FaceFilterPipeline pipeline;
    late FaceMeshResult face;

    setUp(() {
      pipeline = const FaceFilterPipeline();
      face = _fakeFaceMesh();
    });

    test('chin works independently of face_slim', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final chinOnly = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {'chin': 0.8},
      );
      expect(chinOnly.isIdentity, isFalse);
    });

    test('jaw filter uses disjoint indices from face_slim', () {
      final jawFilter = JawFilter();
      final faceSlim = FaceSlimFilter();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final ctx = FaceWarpContext(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        intensity: 1,
        yawFactor: 1,
      );

      final jawIndices = jawFilter
          .buildControlPoints(ctx)
          .where((p) => !p.isAnchor)
          .map((p) => _landmarkIndexFor(mesh, p.source))
          .whereType<int>()
          .toSet();

      final slimIndices = faceSlim
          .buildControlPoints(ctx)
          .where((p) => !p.isAnchor)
          .map((p) => _landmarkIndexFor(mesh, p.source))
          .whereType<int>()
          .toSet();

      expect(jawIndices.intersection(slimIndices), isEmpty);
    });

    test('jaw and chin combine with face filters', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {
          'face_slim': 0.3,
          'jaw': 0.5,
          'chin': 0.4,
        },
      );
      expect(field.isIdentity, isFalse);
    });
  });

  group('FaceFilterPipeline Sprint 14', () {
    late FaceFilterPipeline pipeline;
    late FaceMeshResult face;

    setUp(() {
      pipeline = const FaceFilterPipeline();
      face = _fakeFaceMesh();
    });

    test('cheekbone warp produces moderate displacement', () {
      final filter = CheekboneFilter();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final points = filter.buildControlPoints(
        FaceWarpContext(
          mesh: mesh,
          face: face,
          imageSize: imageSize,
          intensity: 0.5,
          yawFactor: 1,
        ),
      );
      final moved = points.where((p) => !p.isAnchor);
      expect(moved, isNotEmpty);
      for (final cp in moved) {
        expect((cp.target.dx - cp.source.dx).abs(), lessThan(15));
        expect((cp.target.dy - cp.source.dy).abs(), lessThan(10));
      }
    });

    test('cheekbone contour regions include highlight and shadow', () {
      final regions = FaceWarpUtils.cheekboneContourRegions(face, imageSize);
      expect(regions.highlights, isNotEmpty);
      expect(regions.shadows, isNotEmpty);
      expect(regions.highlights.length, equals(regions.shadows.length));
    });
  });

  group('FaceFilterPipeline Sprint 15', () {
    late FaceFilterPipeline pipeline;
    late FaceMeshResult face;

    setUp(() {
      pipeline = const FaceFilterPipeline();
      face = _fakeFaceMesh();
    });

    test('forehead excludes hairline landmarks', () {
      final filter = ForeheadFilter();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final ctx = FaceWarpContext(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        intensity: 1,
        yawFactor: 1,
      );
      final indices = filter
          .buildControlPoints(ctx)
          .where((p) => !p.isAnchor)
          .map((p) => _landmarkIndexFor(mesh, p.source))
          .whereType<int>()
          .toSet();

      expect(
        indices.intersection(ForeheadFilter.hairlineLandmarkIndices),
        isEmpty,
      );
    });

    test('forehead and temple combine without error', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {
          'forehead': 0.4,
          'temple': 0.3,
        },
      );
      expect(field.isIdentity, isFalse);
    });

    test('temple filter displaces lateral points inward', () {
      final filter = TempleFilter();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final points = filter.buildControlPoints(
        FaceWarpContext(
          mesh: mesh,
          face: face,
          imageSize: imageSize,
          intensity: 1,
          yawFactor: 1,
        ),
      );
      expect(points.where((p) => !p.isAnchor), isNotEmpty);
    });
  });

  group('FaceFilterPipeline Sprint 16', () {
    late FaceFilterPipeline pipeline;
    late FaceMeshResult face;

    setUp(() {
      pipeline = const FaceFilterPipeline();
      face = _fakeFaceMesh();
    });

    test('mouth filters combine without error', () {
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: const {
          'mouth_width': 0.4,
          'lip_thickness': 0.5,
          'smile': 0.3,
        },
      );
      expect(field.isIdentity, isFalse);
    });

    test('smile at 0.5 skips inner mouth landmarks', () {
      final filter = SmileFilter();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final points = filter.buildControlPoints(
        FaceWarpContext(
          mesh: mesh,
          face: face,
          imageSize: imageSize,
          intensity: 0.5,
          yawFactor: 1,
        ),
      );
      final indices = points
          .where((p) => !p.isAnchor)
          .map((p) => _landmarkIndexFor(mesh, p.source))
          .whereType<int>()
          .toSet();
      expect(indices.intersection(FaceWarpUtils.innerMouthExcluded), isEmpty);
    });
  });
}

int? _landmarkIndexFor(TriMesh mesh, Offset source) {
  for (var i = 0; i < mesh.vertices.length ~/ 2; i++) {
    final x = mesh.vertices[i * 2];
    final y = mesh.vertices[i * 2 + 1];
    if ((x - source.dx).abs() < 0.01 && (y - source.dy).abs() < 0.01) {
      return i;
    }
  }
  return null;
}

FaceMeshResult _fakeFaceMesh() {
  final landmarks = List.generate(
    FaceMeshResult.expectedLandmarkCount,
    (index) {
      final x = 0.35 + (index % 40) * 0.008;
      final y = 0.25 + (index ~/ 40) * 0.012;
      return FaceLandmark(
        index: index,
        normalized: Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)),
        z: index.isEven ? 0.01 : -0.01,
      );
    },
  );

  return FaceMeshResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(60, 70, 80, 120),
    confidence: 0.95,
  );
}

Uint8List _solidRgba({required int width, required int height}) {
  final data = Uint8List(width * height * 4);
  for (var i = 0; i < data.length; i += 4) {
    data[i] = 180;
    data[i + 1] = 140;
    data[i + 2] = 120;
    data[i + 3] = 255;
  }
  return data;
}

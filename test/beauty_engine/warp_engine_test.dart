import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_algorithm.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/models/control_point.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/mls_solver.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/mls_warp_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine_factory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(200, 300);

  group('MlsWarpEngine', () {
    late MlsWarpEngine engine;
    late FaceMeshResult face;
    late WarpRequest baseRequest;

    setUp(() {
      engine = MlsWarpEngine(
        fieldBuilder: const WarpFieldBuilder(gridWidth: 16, gridHeight: 16),
      );
      face = _fakeFaceMesh();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      baseRequest = WarpRequest(
        mesh: mesh,
        region: MeshRegion.jawLeft,
        parameters: const {},
        imageSize: imageSize,
      );
    });

    test('intensity 0 returns identity field', () {
      final field = engine.compute(baseRequest);
      expect(field.isIdentity, isTrue);
    });

    test('face_slim moves jaw control points inward', () {
      final zero = engine.compute(baseRequest);
      expect(zero.controlPoints, isEmpty);

      final request = WarpRequest(
        mesh: baseRequest.mesh,
        region: MeshRegion.jawLeft,
        parameters: const {'face_slim': 1.0},
        imageSize: imageSize,
      );
      final field = engine.compute(request);

      expect(field.isIdentity, isFalse);
      expect(field.controlPoints, isNotEmpty);

      final moved = field.controlPoints.where((cp) => !cp.isAnchor);
      expect(moved, isNotEmpty);

      final centerX = imageSize.width / 2;
      var movedInward = 0;
      for (final cp in moved) {
        final before = (cp.source.dx - centerX).abs();
        final after = (cp.target.dx - centerX).abs();
        if (after < before) {
          movedInward++;
        }
      }
      expect(movedInward, greaterThan(0));
    });

    test('reset returns identity field', () {
      engine.compute(WarpRequest(
        mesh: baseRequest.mesh,
        region: MeshRegion.jawLeft,
        parameters: const {'face_slim': 0.8},
        imageSize: imageSize,
      ));

      final reset = engine.reset();
      expect(reset.isIdentity, isTrue);
    });
  });

  group('WarpCpuRemap', () {
    test('pixels outside mask remain unchanged', () {
      final face = _fakeFaceMesh();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final engine = MlsWarpEngine(
        fieldBuilder: const WarpFieldBuilder(gridWidth: 16, gridHeight: 16),
      );
      final field = engine.compute(WarpRequest(
        mesh: mesh,
        region: MeshRegion.jawLeft,
        parameters: const {'face_slim': 1.0},
        imageSize: imageSize,
      ));

      final rgba = _solidImage(width: 200, height: 300, r: 100, g: 150, b: 200);
      final original = Uint8List.fromList(rgba);

      final output = const WarpCpuRemap().apply(
        rgba: rgba,
        width: 200,
        height: 300,
        field: field,
      );

      var topLeftUnchanged = true;
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 20; x++) {
          final idx = (y * 200 + x) * 4;
          if (output[idx] != original[idx] ||
              output[idx + 1] != original[idx + 1] ||
              output[idx + 2] != original[idx + 2]) {
            topLeftUnchanged = false;
          }
        }
      }
      expect(topLeftUnchanged, isTrue);
    });

    test('pixels inside mask change with face_slim', () {
      final face = _fakeFaceMesh();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final engine = MlsWarpEngine(
        fieldBuilder: const WarpFieldBuilder(gridWidth: 16, gridHeight: 16),
      );

      final identity = WarpField.identity(
        imageSize: imageSize,
        region: MeshRegion.jawLeft,
      );
      final warped = engine.compute(WarpRequest(
        mesh: mesh,
        region: MeshRegion.jawLeft,
        parameters: const {'face_slim': 1.0},
        imageSize: imageSize,
      ));

      final rgba = _gradientImage(width: 200, height: 300);
      const remapper = WarpCpuRemap();

      final outIdentity = remapper.apply(
        rgba: Uint8List.fromList(rgba),
        width: 200,
        height: 300,
        field: identity,
      );
      final outWarped = remapper.apply(
        rgba: Uint8List.fromList(rgba),
        width: 200,
        height: 300,
        field: warped,
      );

      var diffInside = 0;
      for (var y = 80; y < 220; y++) {
        for (var x = 60; x < 140; x++) {
          final idx = (y * 200 + x) * 4;
          if (outIdentity[idx] != outWarped[idx]) {
            diffInside++;
          }
        }
      }
      expect(diffInside, greaterThan(0));
    });
  });

  group('GPURendererStub warp pass', () {
    test('applyGPU via renderer produces warped texture', () async {
      final renderer = GPURendererStub();
      final engine = MlsWarpEngine(
        fieldBuilder: const WarpFieldBuilder(gridWidth: 16, gridHeight: 16),
      );

      final mesh = const FaceMeshBuilder().build(_fakeFaceMesh(), imageSize);
      final field = engine.compute(WarpRequest(
        mesh: mesh,
        region: MeshRegion.jawLeft,
        parameters: const {'face_slim': 0.9},
        imageSize: imageSize,
      ));

      final rgba = _solidImage(width: 200, height: 300, r: 50, g: 100, b: 150);
      final input = await renderer.upload(
        TextureUpload(bytes: rgba, width: 200, height: 300),
      );

      final output = await engine.applyGPU(
        input: input,
        field: field,
        renderer: renderer,
      );

      expect(output.id, isNot(input.id));
      final pixels = await renderer.readPixels(output);
      expect(pixels.length, rgba.length);
    });
  });

  group('WarpEngineFactory stubs', () {
    test('TPS throws UnimplementedError', () {
      expect(
        () => WarpEngineFactory.create(WarpAlgorithm.thinPlateSpline).compute(
              WarpRequest(
                mesh: const FaceMeshBuilder().build(_fakeFaceMesh(), imageSize),
                region: MeshRegion.jawLeft,
                parameters: const {},
                imageSize: imageSize,
              ),
            ),
        throwsUnimplementedError,
      );
    });
  });

  group('MlsSolver', () {
    test('anchor-only points return same position', () {
      const cp = ControlPoint(
        source: Offset(50, 50),
        target: Offset(50, 50),
      );
      final result = MlsSolver.forward([cp], const Offset(80, 90));
      expect(result, const Offset(80, 90));
    });
  });
}

FaceMeshResult _fakeFaceMesh() {
  final landmarks = List.generate(
    FaceMeshResult.expectedLandmarkCount,
    (index) {
      final x = 0.25 + (index % 40) * 0.012;
      final y = 0.15 + (index ~/ 40) * 0.015;
      return FaceLandmark(
        index: index,
        normalized: Offset(x, y),
      );
    },
  );

  return FaceMeshResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTRB(0.2, 0.15, 0.8, 0.85),
    confidence: 0.9,
  );
}

Uint8List _gradientImage({required int width, required int height}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final idx = (y * width + x) * 4;
      bytes[idx] = (x * 255 / width).round();
      bytes[idx + 1] = (y * 255 / height).round();
      bytes[idx + 2] = ((x + y) * 255 / (width + height)).round();
      bytes[idx + 3] = 255;
    }
  }
  return bytes;
}

Uint8List _solidImage({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
}) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final idx = i * 4;
    bytes[idx] = r;
    bytes[idx + 1] = g;
    bytes[idx + 2] = b;
    bytes[idx + 3] = 255;
  }
  return bytes;
}

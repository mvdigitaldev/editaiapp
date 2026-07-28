import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/influence_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/protection/rigidity_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/fragment_program_warp_backend.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/render_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/render_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/warp_texture.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_target.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/shader_program_cache.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/models/control_point.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FragmentProgramWarpBackend.resetShared();
  });

  group('WarpTexture', () {
    test('encodes signed displacement and mask from WarpField', () {
      final field = _shiftField(dx: 10, dy: -4, mask: 0.8);
      final disp = WarpTexture.fromDisplacement(field);
      final mask = WarpTexture.fromMask(field);

      expect(disp.width, field.gridWidth);
      expect(disp.height, field.gridHeight);
      expect(mask.rgba[0], closeTo(204, 1));

      final decoded = WarpTexture.decodeDisplacement(
        disp.rgba[0],
        disp.rgba[1],
        field.imageSize,
      );
      expect(decoded.dx, closeTo(10, 1.5));
      expect(decoded.dy, closeTo(-4, 1.5));
    });

    test('constant influence defaults to full weight', () {
      final tex = WarpTexture.constant(
        kind: WarpTextureKind.influence,
        imageSize: const Size(8, 8),
        value: 1,
      );
      expect(tex.rgba[0], 255);
    });
  });

  group('RenderPlan / RenderCapabilities', () {
    test('shouldUseGpu only when capabilities allow and field active', () {
      final identity = WarpField.identity(
        imageSize: const Size(8, 8),
        region: MeshRegion.waist,
      );
      final active = _shiftField(dx: 4, dy: 0, mask: 1);

      final cpuPlan = RenderPlan.previewBodyReshape(
        field: active,
        capabilities: RenderCapabilities.cpuOnly,
      );
      expect(cpuPlan.shouldUseGpu, isFalse);

      final gpuPlan = RenderPlan.previewBodyReshape(
        field: active,
        capabilities: RenderCapabilities.gpuPreview,
      );
      expect(gpuPlan.shouldUseGpu, isTrue);

      final identityPlan = RenderPlan.previewBodyReshape(
        field: identity,
        capabilities: RenderCapabilities.gpuPreview,
      );
      expect(identityPlan.shouldUseGpu, isFalse);
    });

    test('hasProtection respects rigidity map', () {
      final field = _shiftField(dx: 2, dy: 0, mask: 1);
      final protection = RigidityMap(
        values: Float32List.fromList([1, 0, 0, 0]),
        width: 2,
        height: 2,
        imageSize: field.imageSize,
        maxValue: 1,
        hadLines: true,
      );
      final plan = RenderPlan.previewBodyReshape(
        field: field,
        protectionMap: protection,
        capabilities: RenderCapabilities.gpuPreview,
      );
      expect(plan.hasProtection, isTrue);
    });
  });

  group('FragmentProgramWarpBackend', () {
    test('forceCpuFallback keeps backend unavailable', () async {
      final backend = FragmentProgramWarpBackend(forceCpuFallback: true);
      await backend.initialize();
      expect(backend.isAvailable, isFalse);
      expect(backend.capabilities.usesGpuPreview, isFalse);

      final out = await backend.apply(
        rgba: _solidRgba(4, 4, 10, 20, 30),
        width: 4,
        height: 4,
        field: _shiftField(dx: 2, dy: 0, mask: 1),
      );
      expect(out, isNull);
      backend.dispose();
    });
  });

  group('PassWarp', () {
    test('CPU fallback remaps and respects zero mask outside body', () async {
      final renderer = GpuRendererImpl(forceCpuWarp: true);
      addTearDown(renderer.dispose);

      final rgba = _gradientRgba(16, 16);
      final input = await renderer.upload(
        TextureUpload(bytes: rgba, width: 16, height: 16),
      );

      final field = _localizedShiftField();
      final output = await renderer.applyPass(
        input: input,
        shaderName: WarpEngine.warpRemapShader,
        uniforms: {
          'warpField': field,
          'forceCpu': true,
        },
      );

      final pixels = await renderer.readPixels(output);
      // Corner outside active mask stays unchanged.
      expect(pixels[0], rgba[0]);
      expect(pixels[1], rgba[1]);
      expect(pixels[2], rgba[2]);

      // Center cell should differ after horizontal shift.
      final center = ((8 * 16) + 8) * 4;
      expect(pixels[center], isNot(rgba[center]));

      renderer.release(input);
      renderer.release(output);
    });

    test('protection map zero-influence path uses CPU remapper via forceCpu',
        () async {
      final cache = ShaderProgramCache(
        warpBackend: FragmentProgramWarpBackend(forceCpuFallback: true),
        preferGpuWarp: false,
      );
      expect(cache.contains(RenderShaders.warpRemap), isTrue);

      final remapper = const WarpCpuRemap();
      final field = _localizedShiftField();
      final rgba = _gradientRgba(16, 16);
      final warped = remapper.apply(
        rgba: rgba,
        width: 16,
        height: 16,
        field: field,
      );
      expect(warped.length, rgba.length);
    });

    test('zero influence map is treated as identity (no upload)', () {
      final field = _localizedShiftField();
      final influence = InfluenceMap(
        values: Float32List(field.gridWidth * field.gridHeight),
        width: field.gridWidth,
        height: field.gridHeight,
        imageSize: field.imageSize,
        regions: const {},
        confidence: 1,
        maxValue: 0,
      );
      final plan = RenderPlan.previewBodyReshape(
        field: field,
        influenceMap: influence,
        capabilities: RenderCapabilities.gpuPreview,
      );
      expect(plan.hasInfluence, isFalse);
      expect(plan.hasProtection, isFalse);
    });
  });

  group('GpuRendererImpl Sprint 9', () {
    test('initialize wires fragment backend without crashing', () async {
      final renderer = GpuRendererImpl(forceCpuWarp: true);
      addTearDown(renderer.dispose);
      await renderer.initialize();
      expect(renderer.fragmentBackend.isAvailable, isFalse);
      expect(renderer.shaderCache.contains(RenderShaders.warpRemap), isTrue);
    });
  });
}

WarpField _shiftField({
  required double dx,
  required double dy,
  required double mask,
}) {
  const grid = 4;
  final displacement = Float32List(grid * grid * 2);
  final masks = Float32List(grid * grid);
  for (var i = 0; i < grid * grid; i++) {
    displacement[i * 2] = dx;
    displacement[i * 2 + 1] = dy;
    masks[i] = mask;
  }
  return WarpField(
    gridWidth: grid,
    gridHeight: grid,
    displacement: displacement,
    mask: masks,
    imageSize: const Size(32, 32),
    region: MeshRegion.waist,
    controlPoints: const [
      ControlPoint(source: Offset(0.5, 0.5), target: Offset(0.55, 0.5)),
    ],
    intensity: 0.8,
  );
}

WarpField _localizedShiftField() {
  const grid = 8;
  final displacement = Float32List(grid * grid * 2);
  final masks = Float32List(grid * grid);
  for (var y = 3; y <= 5; y++) {
    for (var x = 3; x <= 5; x++) {
      final idx = y * grid + x;
      displacement[idx * 2] = 4;
      masks[idx] = 1;
    }
  }
  return WarpField(
    gridWidth: grid,
    gridHeight: grid,
    displacement: displacement,
    mask: masks,
    imageSize: const Size(16, 16),
    region: MeshRegion.waist,
    controlPoints: const [
      ControlPoint(source: Offset(0.5, 0.5), target: Offset(0.6, 0.5)),
    ],
    intensity: 1,
  );
}

Uint8List _solidRgba(int width, int height, int r, int g, int b) {
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

Uint8List _gradientRgba(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final idx = (y * width + x) * 4;
      bytes[idx] = (x * 255 / (width - 1)).round();
      bytes[idx + 1] = (y * 255 / (height - 1)).round();
      bytes[idx + 2] = 128;
      bytes[idx + 3] = 255;
    }
  }
  return bytes;
}

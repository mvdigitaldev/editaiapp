import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/export_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/fragment_program_warp_backend.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/memory_budget.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/method_channel_native_export_backend.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/native_export_backend.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/render_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/adaptive_preview_policy.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/image_tile_grid.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/models/control_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FragmentProgramWarpBackend.resetShared();
  });

  group('MemoryBudget', () {
    test('tiled peak for 12MP stays under export budget', () {
      // ~4000x3000
      final peak = MemoryBudget.estimateTiledExportPeakBytes(
        fullWidth: 4000,
        fullHeight: 3000,
        haloPx: MemoryBudget.defaultTileHaloPx,
      );
      expect(peak, lessThan(MemoryBudget.exportPeakBytes));
      expect(
        MemoryBudget.fitsExportBudget(fullWidth: 4000, fullHeight: 3000),
        isTrue,
      );
    });

    test('halo grows with displacement and clamps', () {
      expect(MemoryBudget.haloForMaxDisplacement(10), 64);
      expect(MemoryBudget.haloForMaxDisplacement(100), 108);
      expect(
        MemoryBudget.haloForMaxDisplacement(500),
        MemoryBudget.maxTileHaloPx,
      );
    });
  });

  group('ImageTileGrid halo', () {
    test('expanded tiles cover neighbors and write interior only', () {
      const fullW = 64;
      const fullH = 64;
      final full = Uint8List(fullW * fullH * 4);
      for (var i = 0; i < full.length; i += 4) {
        full[i] = 10;
        full[i + 1] = 20;
        full[i + 2] = 30;
        full[i + 3] = 255;
      }

      final tiles = ImageTileGrid.specsFor(
        fullWidth: fullW,
        fullHeight: fullH,
        tileSize: 32,
        haloPx: 8,
      );
      expect(tiles, hasLength(4));
      expect(tiles.first.padLeft, 0);
      expect(tiles.first.padRight, 8);
      expect(tiles.first.expandWidth, 40);

      final expanded = ImageTileGrid.extractExpandedTile(
        fullRgba: full,
        fullWidth: fullW,
        fullHeight: fullH,
        tile: tiles.first,
      );
      expect(expanded.length, 40 * 40 * 4);

      // Marca interior expandido e escreve de volta.
      for (var i = 0; i < expanded.length; i += 4) {
        expanded[i] = 200;
      }
      final out = Uint8List.fromList(full);
      ImageTileGrid.writeInteriorFromExpanded(
        fullRgba: out,
        fullWidth: fullW,
        tile: tiles.first,
        expandedRgba: expanded,
      );

      // Interior (0..31,0..31) atualizado; pixel em x=36 (só halo) intacto na imagem.
      expect(out[0], 200);
      final haloOnlyIndex = (0 * fullW + 36) * 4;
      expect(out[haloOnlyIndex], 10);
    });
  });

  group('ExportWarp', () {
    test('uses native backend when available without Dart CPU loop', () async {
      final fake = FakeNativeExportBackend(
        capabilities: const ExportWarpCapabilities(openGlEs: true),
      );
      final export = ExportWarp(
        fragmentBackend: FragmentProgramWarpBackend(forceCpuFallback: true),
        nativeBackend: fake,
      );

      final rgba = Uint8List(8 * 8 * 4);
      final field = _shiftField(dx: 2, dy: 0, mask: 1);
      final result = await export.apply(
        ExportWarpRequest(
          rgba: rgba,
          width: 8,
          height: 8,
          field: field,
          allowCpuFallback: false,
        ),
      );

      expect(fake.warpCallCount, 1);
      expect(result.backend, ExportWarpBackendKind.vulkanOrGles);
      expect(result.usedCpuFallback, isFalse);
      expect(result.rgba.length, rgba.length);
    });

    test('throws when GPU unavailable and CPU not allowed', () async {
      final export = ExportWarp(
        fragmentBackend: FragmentProgramWarpBackend(forceCpuFallback: true),
        nativeBackend: FakeNativeExportBackend(
          capabilities: ExportWarpCapabilities.unavailable,
          warpHandler: (_) async => null,
        ),
      );

      expect(
        () => export.apply(
          ExportWarpRequest(
            rgba: Uint8List(16),
            width: 2,
            height: 2,
            field: _shiftField(dx: 1, dy: 0, mask: 1),
            allowCpuFallback: false,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('explicit CPU fallback is labeled', () async {
      final export = ExportWarp(
        fragmentBackend: FragmentProgramWarpBackend(forceCpuFallback: true),
        nativeBackend: FakeNativeExportBackend(
          capabilities: ExportWarpCapabilities.unavailable,
        ),
      );

      final result = await export.apply(
        ExportWarpRequest(
          rgba: Uint8List(4 * 4 * 4),
          width: 4,
          height: 4,
          field: _shiftField(dx: 1, dy: 0, mask: 1),
          allowCpuFallback: true,
        ),
      );

      expect(result.backend, ExportWarpBackendKind.cpuExplicit);
      expect(result.usedCpuFallback, isTrue);
    });

    test('tiled CPU fallback rejects a tile without global source', () async {
      final export = ExportWarp(
        fragmentBackend: FragmentProgramWarpBackend(forceCpuFallback: true),
      );

      await expectLater(
        export.apply(
          ExportWarpRequest(
            rgba: Uint8List(4 * 4 * 4),
            width: 4,
            height: 4,
            field: _shiftField(dx: 1, dy: 0, mask: 1),
            tileOriginX: 4,
            fullWidth: 8,
            fullHeight: 8,
            allowCpuFallback: true,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cpu_tile_requires_full_source'),
          ),
        ),
      );
    });
  });

  group('RenderPlan.exportBodyReshape', () {
    test('carries tile origin and export quality profile', () {
      final field = _shiftField(dx: 3, dy: 1, mask: 0.5);
      final plan = RenderPlan.exportBodyReshape(
        field: field,
        tileOriginX: 64,
        tileOriginY: 128,
        fullWidth: 2048,
        fullHeight: 2048,
      );
      expect(plan.qualityProfile, same(WarpQualityProfile.export));
      expect(plan.tileOriginX, 64);
      expect(plan.fullWidth, 2048);
    });
  });

  group('WarpField.maxDisplacementMagnitude', () {
    test('reports peak vector length', () {
      final field = _shiftField(dx: 3, dy: 4, mask: 1);
      expect(field.maxDisplacementMagnitude, closeTo(5, 1e-6));
    });
  });

  test('tiled threshold remains 8MP', () {
    expect(AdaptivePreviewPolicy.tiledExportMegapixelThreshold, 8.0);
    expect(MemoryBudget.tiledExportMegapixels, 8.0);
  });
}

WarpField _shiftField({
  required double dx,
  required double dy,
  required double mask,
}) {
  const size = Size(32, 32);
  const gw = 4;
  const gh = 4;
  final displacement = Float32List(gw * gh * 2);
  final masks = Float32List(gw * gh);
  for (var i = 0; i < gw * gh; i++) {
    displacement[i * 2] = dx;
    displacement[i * 2 + 1] = dy;
    masks[i] = mask;
  }
  return WarpField(
    gridWidth: gw,
    gridHeight: gh,
    displacement: displacement,
    mask: masks,
    imageSize: size,
    region: MeshRegion.torso,
    intensity: 1,
    controlPoints: [
      ControlPoint(
        source: const Offset(0.5, 0.5),
        target: Offset(0.5 + dx / 32, 0.5 + dy / 32),
      ),
    ],
  );
}

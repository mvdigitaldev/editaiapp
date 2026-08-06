import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../models/warp_field.dart';
import '../../warp/models/control_point.dart';
import '../deformation/body_mesh_deformer.dart';
import '../maps/protection_maps.dart';
import '../mesh/adaptive_body_mesh.dart';
import '../mesh/mesh_optimizer.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// Rasteriza deslocamentos de malha adaptativa em um [WarpField] de grade.
///
/// O remap GPU usa mapeamento inverso (`src = p + d`). Esta pass rasteriza
/// no espaço do **destino** (malha deformada) e grava `d = origem − destino`.
class BodyMeshWarpPass implements BodyReshapePass {
  const BodyMeshWarpPass({
    this.deformer = const BodyMeshDeformer(),
    // Grade mais fina reduz o gradiente por célula e evita que o anti-dobra
    // precise achatar o campo (origem do efeito "quebrado").
    this.gridWidth = 96,
    this.gridHeight = 96,
    this.minDisplacementPx = 0.05,
    this.outerDiffuseIterations = 4,
  });

  final BodyMeshDeformer deformer;
  final int gridWidth;
  final int gridHeight;
  final double minDisplacementPx;
  final int outerDiffuseIterations;

  @override
  String get id => 'body_mesh_warp';

  @override
  bool isEnabled(BodyMultiPassConfig config) => config.bodyMeshWarp;

  @override
  WarpField run(BodyPassContext context) {
    final mesh = context.sourceMesh;
    final assets = context.assets;
    final plan = context.plan;
    if (mesh == null || assets == null || plan == null || plan.isIdentity) {
      context.field ??= WarpField.identity(
        imageSize: context.imageSize,
        region: context.region,
      );
      return context.requireField;
    }

    final optimized = deformer.deform(mesh: mesh, assets: assets, plan: plan);
    context.optimizedMesh = optimized.mesh;
    context.vertexDisplacements = optimized.displacements;
    context.controlPoints = controlPointsFromDisplacements(
      source: mesh,
      displacements: optimized.displacements,
      minDisplacementPx: minDisplacementPx,
    );

    final field = rasterize(
      source: mesh,
      deformed: optimized.mesh,
      displacements: optimized.displacements,
      imageSize: context.imageSize,
      region: context.region,
      intensity: plan.maxIntensity,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      protectionMaps: context.protectionMaps,
      outerDiffuseIterations: outerDiffuseIterations,
    );
    context.field = field;
    context.intermediateBuffers['mesh_disp'] =
        Float32List.fromList(optimized.displacements.deltas);
    return field;
  }

  /// Converte vértices com deslocamento significativo em CPs esparsos (LocalMls).
  static List<ControlPoint> controlPointsFromDisplacements({
    required AdaptiveBodyMesh source,
    required VertexDisplacementField displacements,
    double minDisplacementPx = 0.05,
    int maxPoints = 256,
  }) {
    final scored = <({int index, double mag})>[];
    for (var i = 0; i < source.vertexCount; i++) {
      final mag = displacements.magnitudeAt(i);
      if (mag >= minDisplacementPx) {
        scored.add((index: i, mag: mag));
      }
    }
    scored.sort((a, b) => b.mag.compareTo(a.mag));
    final take = math.min(maxPoints, scored.length);
    final points = <ControlPoint>[];
    for (var i = 0; i < take; i++) {
      final idx = scored[i].index;
      final sx = source.vertices[idx * 2];
      final sy = source.vertices[idx * 2 + 1];
      final d = displacements.deltaAt(idx);
      points.add(
        ControlPoint(
          source: Offset(sx, sy),
          target: Offset(sx + d.dx, sy + d.dy),
        ),
      );
    }
    return points;
  }

  /// Amostra barycentric no espaço **destino** e grava `d = origem − destino`.
  static WarpField rasterize({
    required AdaptiveBodyMesh source,
    required AdaptiveBodyMesh deformed,
    required VertexDisplacementField displacements,
    required Size imageSize,
    required MeshRegion region,
    required double intensity,
    int gridWidth = 64,
    int gridHeight = 64,
    ProtectionMaps? protectionMaps,
    int outerDiffuseIterations = 4,
  }) {
    if (displacements.isIdentity ||
        source.triangleCount == 0 ||
        deformed.triangleCount == 0) {
      return WarpField.identity(imageSize: imageSize, region: region);
    }

    final cellCount = gridWidth * gridHeight;
    final disp = Float32List(cellCount * 2);
    final mask = Float32List(cellCount);
    // Índice espacial sobre a malha DEFORMADA (espaço do destino).
    final index = TriangleSpatialIndex(deformed);
    var active = 0;

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final px = (gx / (gridWidth - 1)) * imageSize.width;
        final py = (gy / (gridHeight - 1)) * imageSize.height;
        final hit = index.locate(px, py);
        if (hit == null) {
          continue;
        }
        // Posição de origem interpolada nos vértices da malha original.
        final sx0 = source.vertices[hit.i0 * 2];
        final sy0 = source.vertices[hit.i0 * 2 + 1];
        final sx1 = source.vertices[hit.i1 * 2];
        final sy1 = source.vertices[hit.i1 * 2 + 1];
        final sx2 = source.vertices[hit.i2 * 2];
        final sy2 = source.vertices[hit.i2 * 2 + 1];
        final srcX = sx0 * hit.w0 + sx1 * hit.w1 + sx2 * hit.w2;
        final srcY = sy0 * hit.w0 + sy1 * hit.w1 + sy2 * hit.w2;
        // Campo inverso: src = p + d  ⇒  d = src − p
        final dx = srcX - px;
        final dy = srcY - py;
        final idx = gy * gridWidth + gx;
        disp[idx * 2] = dx;
        disp[idx * 2 + 1] = dy;
        final mag = math.sqrt(dx * dx + dy * dy);
        // Máscara = domínio do warp, não amplitude. O shader multiplica
        // disp × mask × edgeScale², então modular a máscara pela magnitude
        // atenuaria o campo duas vezes (efeito quase invisível).
        mask[idx] = (mag / 0.5).clamp(0.0, 1.0);
        if (mask[idx] > 0) {
          active++;
        }
      }
    }

    // Região abandonada pelo slim (ainda no matte original, fora da malha
    // deformada): aproxima o inverso com −δ_forward na malha fonte.
    final sourceIndex = TriangleSpatialIndex(source);
    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final idx = gy * gridWidth + gx;
        if (mask[idx] > 1e-4) {
          continue;
        }
        final px = (gx / (gridWidth - 1)) * imageSize.width;
        final py = (gy / (gridHeight - 1)) * imageSize.height;
        final hit = sourceIndex.locate(px, py);
        if (hit == null) {
          continue;
        }
        final d0 = displacements.deltaAt(hit.i0);
        final d1 = displacements.deltaAt(hit.i1);
        final d2 = displacements.deltaAt(hit.i2);
        final fdx = d0.dx * hit.w0 + d1.dx * hit.w1 + d2.dx * hit.w2;
        final fdy = d0.dy * hit.w0 + d1.dy * hit.w1 + d2.dy * hit.w2;
        final mag = math.sqrt(fdx * fdx + fdy * fdy);
        if (mag <= 1e-6) {
          continue;
        }
        // Inverso aproximado no espaço fonte.
        disp[idx * 2] = -fdx;
        disp[idx * 2 + 1] = -fdy;
        mask[idx] = (mag / 0.5).clamp(0.0, 1.0);
        active++;
      }
    }

    // Difunde deslocamento na banda exterior do SDF (fecha gap do slim).
    if (protectionMaps != null &&
        !protectionMaps.isEmpty &&
        outerDiffuseIterations > 0) {
      active = _diffuseOuterBand(
        disp: disp,
        mask: mask,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        imageSize: imageSize,
        protectionMaps: protectionMaps,
        iterations: outerDiffuseIterations,
        active: active,
      );
    }

    return WarpField(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      displacement: disp,
      mask: mask,
      imageSize: imageSize,
      region: region,
      controlPoints: const [],
      intensity: intensity.clamp(0.0, 1.0),
      passId: 'body_mesh_warp',
      activeCellCount: active,
    );
  }

  /// Dilata o campo para células exteriores com peso de warp > 0.
  static int _diffuseOuterBand({
    required Float32List disp,
    required Float32List mask,
    required int gridWidth,
    required int gridHeight,
    required Size imageSize,
    required ProtectionMaps protectionMaps,
    required int iterations,
    required int active,
  }) {
    final sdf = protectionMaps.sdf;
    final outerBand = math.max(
      protectionMaps.outerBandPx,
      protectionMaps.transitionPx,
    );
    if (outerBand <= 0 || sdf.isEmpty) {
      return active;
    }

    // Escala SDF (resolução do matte) → pixels da imagem.
    final sdfScaleX = imageSize.width / math.max(sdf.width, 1);
    final sdfScaleY = imageSize.height / math.max(sdf.height, 1);
    final sdfScale = (sdfScaleX + sdfScaleY) * 0.5;

    var currentActive = active;
    for (var iter = 0; iter < iterations; iter++) {
      final nextDisp = Float32List.fromList(disp);
      final nextMask = Float32List.fromList(mask);
      var grew = 0;

      for (var gy = 0; gy < gridHeight; gy++) {
        for (var gx = 0; gx < gridWidth; gx++) {
          final idx = gy * gridWidth + gx;
          final nx = gx / (gridWidth - 1);
          final ny = gy / (gridHeight - 1);
          final weight = protectionMaps.sampleWarpWeight(nx, ny);
          if (weight <= 1e-4) {
            continue;
          }

          final sdfDist = sdf.sampleNormalized(nx, ny) * sdfScale;
          // Só difunde no exterior (sdf > 0) dentro da banda.
          if (sdfDist <= 0 || sdfDist >= outerBand * sdfScale) {
            // Interior já preenchido pela malha; reforça máscara com peso.
            if (sdfDist <= 0 && mask[idx] > 0) {
              nextMask[idx] = math.max(mask[idx], weight);
            }
            continue;
          }

          // Célula já tem deslocamento forte — só atenua máscara.
          if (mask[idx] > 0.05) {
            nextMask[idx] = math.max(mask[idx] * 0.85, weight);
            continue;
          }

          var sumDx = 0.0;
          var sumDy = 0.0;
          var sumW = 0.0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) {
                continue;
              }
              final x = gx + dx;
              final y = gy + dy;
              if (x < 0 || y < 0 || x >= gridWidth || y >= gridHeight) {
                continue;
              }
              final nIdx = y * gridWidth + x;
              final nMask = mask[nIdx];
              if (nMask <= 1e-4) {
                continue;
              }
              final nw = nMask * (dx == 0 || dy == 0 ? 1.0 : 0.707);
              sumDx += disp[nIdx * 2] * nw;
              sumDy += disp[nIdx * 2 + 1] * nw;
              sumW += nw;
            }
          }
          if (sumW <= 1e-6) {
            continue;
          }

          final decay = weight;
          nextDisp[idx * 2] = (sumDx / sumW) * decay;
          nextDisp[idx * 2 + 1] = (sumDy / sumW) * decay;
          nextMask[idx] = decay.clamp(0.0, 1.0);
          grew++;
        }
      }

      for (var i = 0; i < disp.length; i++) {
        disp[i] = nextDisp[i];
      }
      for (var i = 0; i < mask.length; i++) {
        mask[i] = nextMask[i];
      }
      currentActive += grew;
      if (grew == 0) {
        break;
      }
    }
    return currentActive;
  }
}

class BarycentricHit {
  const BarycentricHit({
    required this.i0,
    required this.i1,
    required this.i2,
    required this.w0,
    required this.w1,
    required this.w2,
  });

  final int i0;
  final int i1;
  final int i2;
  final double w0;
  final double w1;
  final double w2;
}

/// Índice espacial de triângulos para localização O(k) por consulta.
class TriangleSpatialIndex {
  TriangleSpatialIndex(AdaptiveBodyMesh mesh) : _mesh = mesh {
    final cell = math.max(
      8.0,
      math.min(mesh.imageSize.width, mesh.imageSize.height) / 32,
    );
    _cellSize = cell;
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      final ax = mesh.vertices[i0 * 2];
      final ay = mesh.vertices[i0 * 2 + 1];
      final bx = mesh.vertices[i1 * 2];
      final by = mesh.vertices[i1 * 2 + 1];
      final cx = mesh.vertices[i2 * 2];
      final cy = mesh.vertices[i2 * 2 + 1];
      final minX = math.min(ax, math.min(bx, cx));
      final maxX = math.max(ax, math.max(bx, cx));
      final minY = math.min(ay, math.min(by, cy));
      final maxY = math.max(ay, math.max(by, cy));
      final x0 = (minX / cell).floor();
      final x1 = (maxX / cell).floor();
      final y0 = (minY / cell).floor();
      final y1 = (maxY / cell).floor();
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          (_triBuckets[SpatialHash2D.pack(x, y)] ??= <int>[]).add(t);
        }
      }
    }
  }

  final AdaptiveBodyMesh _mesh;
  late final double _cellSize;
  final Map<int, List<int>> _triBuckets = {};

  BarycentricHit? locate(double px, double py) {
    final cx = (px / _cellSize).floor();
    final cy = (py / _cellSize).floor();
    final candidates = <int>{};
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final bucket = _triBuckets[SpatialHash2D.pack(cx + dx, cy + dy)];
        if (bucket != null) {
          candidates.addAll(bucket);
        }
      }
    }
    for (final t in candidates) {
      final i0 = _mesh.indices[t * 3];
      final i1 = _mesh.indices[t * 3 + 1];
      final i2 = _mesh.indices[t * 3 + 2];
      final ax = _mesh.vertices[i0 * 2];
      final ay = _mesh.vertices[i0 * 2 + 1];
      final bx = _mesh.vertices[i1 * 2];
      final by = _mesh.vertices[i1 * 2 + 1];
      final cxv = _mesh.vertices[i2 * 2];
      final cyv = _mesh.vertices[i2 * 2 + 1];
      final denom = (by - cyv) * (ax - cxv) + (cxv - bx) * (ay - cyv);
      if (denom.abs() < 1e-12) {
        continue;
      }
      final w0 = ((by - cyv) * (px - cxv) + (cxv - bx) * (py - cyv)) / denom;
      final w1 = ((cyv - ay) * (px - cxv) + (ax - cxv) * (py - cyv)) / denom;
      final w2 = 1.0 - w0 - w1;
      if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) {
        continue;
      }
      return BarycentricHit(i0: i0, i1: i1, i2: i2, w0: w0, w1: w1, w2: w2);
    }
    return null;
  }
}

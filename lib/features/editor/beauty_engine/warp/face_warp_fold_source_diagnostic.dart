import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;
import 'package:image/image.dart' as img;

import '../body_reshape/maps/influence_map.dart';
import '../debug/agent_debug_log.dart';
import '../filters/face/face_warp_utils.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/face_mesh_result.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/anatomical_zone.dart';
import 'anatomy/face_matte_roi.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'anatomy/face_model_specification.dart';
import 'anatomy/pilot_warp_displacement.dart';
import 'anatomy/vertex_role_map.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

/// Resultado Fase 7 — origem do fold no vertex field.
class FaceWarpFoldSourceDiagnosticResult {
  const FaceWarpFoldSourceDiagnosticResult({
    required this.summary,
    required this.summaryJsonPath,
    required this.hotspotsJsonPath,
  });

  final Map<String, dynamic> summary;
  final String summaryJsonPath;
  final String hotspotsJsonPath;
}

/// Fase 7 — diagnosticar fold no vertex field face_slim.
abstract final class FaceWarpFoldSourceDiagnostic {
  FaceWarpFoldSourceDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [
    0.1, 0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.7, 0.9,
  ];

  static const _pngIntensities = [0.3, 0.5, 0.9];

  static Future<FaceWarpFoldSourceDiagnosticResult?> run({
    required FaceMeshResult face,
    required TriMesh mesh,
    required int width,
    required int height,
    PersonMask? personMask,
    String runId = 'fold-source-real',
    String? outputDirectory,
  }) async {
    if (!kDebugMode) {
      return null;
    }

    try {
      final outDir = outputDirectory ?? _defaultOutputDir;
      Directory(outDir).createSync(recursive: true);

      const engine = FaceMeshDeformationEngine();
      final imageSize = Size(width.toDouble(), height.toDouble());
      final influence = FaceMatteRoi.buildInfluenceMap(
        face: face,
        imageSize: imageSize,
        personMask: personMask,
        lateralRadiusExpand: 0.07,
      );

      final sourceIndex = TriMeshSpatialIndex(
        mesh,
        imageWidth: width.toDouble(),
        imageHeight: height.toDouble(),
      );
      final roi = _roiFromMesh(mesh, width, height);
      final neighbors = _buildVertexNeighbors(mesh);
      final edges = _buildUniqueEdges(mesh);
      final zoneLookup = _buildVertexZoneLookup();

      final firstFoldByIntensity = <Map<String, dynamic>>[];
      final minJCoreByIntensity = <Map<String, dynamic>>[];
      final minJEffectiveByIntensity = <Map<String, dynamic>>[];
      final allHotspots = <Map<String, dynamic>>[];
      final compressionViolations = <Map<String, dynamic>>[];
      final monotonicityViolations = <Map<String, dynamic>>[];
      final foldRegionStats = <String, Map<String, dynamic>>{};

      double? firstFoldIntensity;

      for (final intensity in _intensities) {
        debugPrint('P7 fold scan face_slim=$intensity');

        final vertexField = engine.composeVertexField(
          parameters: {'face_slim': intensity},
          context: FaceAnatomyContext(
            face: face,
            imageSize: imageSize,
            mesh: mesh,
          ),
        );
        final payload = FaceMeshForwardPayload(
          mesh: mesh,
          vertexField: vertexField,
          influenceMap: influence,
          personMask: personMask,
        );

        final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
          field: vertexField,
          mesh: mesh,
        );
        final supportWeights = GeometricSupport.computeWeights(
          mesh: mesh,
          coreField: vertexField,
          influenceMap: influence,
          params: const DeformationSupportParams(),
          imageWidth: width,
          imageHeight: height,
          personMask: personMask,
        );

        final jCore = _scanJacobianField(
          sourceIndex: sourceIndex,
          vf: vertexField,
          supportWeights: supportWeights,
          vertexCount: vertexCount,
          roi: roi,
          useCoreOnly: true,
        );
        final jEff = _scanJacobianField(
          sourceIndex: sourceIndex,
          vf: vertexField,
          supportWeights: supportWeights,
          vertexCount: vertexCount,
          roi: roi,
          useCoreOnly: false,
        );

        minJCoreByIntensity.add({'faceSlim': intensity, ...jCore.stats});
        minJEffectiveByIntensity.add({'faceSlim': intensity, ...jEff.stats});

        final minSample = jEff.minSample;
        if (minSample != null) {
          final tri = sourceIndex.locateTriangleIndex(
            minSample.px,
            minSample.py,
          );
          final hit = tri != null
              ? sourceIndex.barycentricInTriangle(tri, minSample.px, minSample.py)
              : null;
          final vertexIds = hit == null
              ? <int>[]
              : [hit.i0, hit.i1, hit.i2];

          firstFoldByIntensity.add({
            'faceSlim': intensity,
            'minJ': minSample.j,
            'minJx': minSample.px,
            'minJy': minSample.py,
            'triangleId': tri,
            'vertexIds': vertexIds,
            'minOnePlusDdxDx': minSample.onePlusDdxDx,
          });

          if (firstFoldIntensity == null && minSample.j <= 0) {
            firstFoldIntensity = intensity;
          }
        }

        for (final hs in jEff.hotspots) {
          final tri = sourceIndex.locateTriangleIndex(hs.px, hs.py);
          final hit = tri != null
              ? sourceIndex.barycentricInTriangle(tri, hs.px, hs.py)
              : null;
          final verts = hit == null
              ? <int>{}
              : {hit.i0, hit.i1, hit.i2, ...?neighbors[hit.i0], ...?neighbors[hit.i1], ...?neighbors[hit.i2]};

          final vertexDetails = <Map<String, dynamic>>[];
          for (final vid in verts) {
            if (vid >= vertexCount) {
              continue;
            }
            final sx = mesh.vertices[vid * 2];
            final sy = mesh.vertices[vid * 2 + 1];
            final core = vertexField.displacementAt(vid);
            final sw = supportWeights[vid].clamp(0.0, 1.0);
            final eff = FaceWarpFieldMetrics.effectiveDelta(core, sw);
            final zone = zoneLookup[vid] ?? 'unknown';
            vertexDetails.add({
              'vertexId': vid,
              'sourceX': sx,
              'sourceY': sy,
              'destinationX': sx + eff.dx,
              'destinationY': sy + eff.dy,
              'coreDx': core.dx,
              'coreDy': core.dy,
              'effectiveDx': eff.dx,
              'effectiveDy': eff.dy,
              'displacementMagnitude': eff.distance,
              'coreMagnitude': core.distance,
              'supportWeight': sw,
              'influenceMapValue': influence.sampleAtPixel(
                sx.round().clamp(0, width - 1),
                sy.round().clamp(0, height - 1),
              ),
              'anatomicalZone': zone,
            });
          }

          final region = _dominantRegion(vertexDetails);
          allHotspots.add({
            'faceSlim': intensity,
            'minJ': hs.j,
            'x': hs.px,
            'y': hs.py,
            'triangleId': tri,
            'gradDx': hs.gradDx,
            'gradDy': hs.gradDy,
            'onePlusDdxDx': hs.onePlusDdxDx,
            'region': region,
            'vertices': vertexDetails,
          });

          final rs = foldRegionStats.putIfAbsent(
            region,
            () => {'hotspotCount': 0, 'minJ': double.infinity, 'compressions': <double>[]},
          );
          rs['hotspotCount'] = (rs['hotspotCount'] as int) + 1;
          rs['minJ'] = math.min(rs['minJ'] as double, hs.j);
        }

        final deformedVerts = _deformedVertices(
          mesh: mesh,
          vf: vertexField,
          supportWeights: supportWeights,
          vertexCount: vertexCount,
        );

        for (final (i, j) in edges) {
          if (i >= vertexCount || j >= vertexCount) {
            continue;
          }
          final ds = _dist(mesh.vertices, i, j);
          final dd = _dist(deformedVerts, i, j);
          if (ds < 1e-6) {
            continue;
          }
          final ratio = dd / ds;
          if (ratio < 0.25) {
            compressionViolations.add({
              'faceSlim': intensity,
              'vertexA': i,
              'vertexB': j,
              'sourceDistance': ds,
              'destinationDistance': dd,
              'compressionRatio': ratio,
              'zoneA': zoneLookup[i],
              'zoneB': zoneLookup[j],
              'orderSwap': _orderSwapHorizontal(mesh.vertices, deformedVerts, i, j),
            });
          }
        }

        monotonicityViolations.addAll(
          _checkMonotonicity(
            face: face,
            mesh: mesh,
            imageSize: imageSize,
            vf: vertexField,
            supportWeights: supportWeights,
            neighbors: neighbors,
            vertexCount: vertexCount,
            intensity: intensity,
            zoneLookup: zoneLookup,
          ),
        );
      }

      final foldRegions = foldRegionStats.entries
          .map(
            (e) => {
              'region': e.key,
              'hotspotCount': e.value['hotspotCount'],
              'minJ': e.value['minJ'],
            },
          )
          .toList();

      final supportEffect = _classifySupportEffect(
        minJCoreByIntensity,
        minJEffectiveByIntensity,
      );

      for (final intensity in _pngIntensities) {
        await _writeVectorFieldPng(
          outDir: outDir,
          face: face,
          mesh: mesh,
          influence: influence,
          personMask: personMask,
          width: width,
          height: height,
          intensity: intensity,
          engine: engine,
          imageSize: imageSize,
          sourceIndex: sourceIndex,
        );
        await _writeCompressionPng(
          outDir: outDir,
          face: face,
          mesh: mesh,
          influence: influence,
          personMask: personMask,
          width: width,
          height: height,
          intensity: intensity,
          engine: engine,
          imageSize: imageSize,
          edges: edges,
        );
      }

      final worstHotspots = allHotspots
        ..sort((a, b) => (a['minJ'] as num).compareTo(b['minJ'] as num));
      final topHotspots = worstHotspots.take(20).toList();

      final hotspotsJsonPath = '$outDir/debug-fold-hotspots.json';
      File(hotspotsJsonPath).writeAsStringSync(jsonEncode(allHotspots));

      final summary = {
        'firstFoldIntensity': firstFoldIntensity,
        'firstFoldByIntensity': firstFoldByIntensity,
        'minJCoreByIntensity': minJCoreByIntensity,
        'minJEffectiveByIntensity': minJEffectiveByIntensity,
        'worstHotspots': topHotspots,
        'foldRegions': foldRegions,
        'compressionViolations': compressionViolations.take(100).toList(),
        'compressionViolationCount': compressionViolations.length,
        'monotonicityViolations': monotonicityViolations.take(50).toList(),
        'monotonicityViolationCount': monotonicityViolations.length,
        'supportEffect': supportEffect,
        'rootComponent': _rootComponentReport(),
        'displacementPipeline': _pipelineReport(),
      };

      final summaryJsonPath = '$outDir/phase7_fold_source_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_fold_source_diagnostic.dart:run',
        message: 'phase7_fold_source_diagnostic',
        hypothesisId: 'P7FS',
        runId: runId,
        phase: '7',
        data: {
          'firstFoldIntensity': firstFoldIntensity,
          'minJCoreByIntensity': minJCoreByIntensity,
          'minJEffectiveByIntensity': minJEffectiveByIntensity,
          'foldRegions': foldRegions,
          'supportEffect': supportEffect,
          'rootComponent': summary['rootComponent'],
          'compressionViolationCount': compressionViolations.length,
          'monotonicityViolationCount': monotonicityViolations.length,
        },
      );

      return FaceWarpFoldSourceDiagnosticResult(
        summary: summary,
        summaryJsonPath: summaryJsonPath,
        hotspotsJsonPath: hotspotsJsonPath,
      );
    } catch (e, st) {
      debugPrint('FaceWarpFoldSourceDiagnostic failed: $e\n$st');
      return null;
    }
  }

  static String _classifySupportEffect(
    List<Map<String, dynamic>> core,
    List<Map<String, dynamic>> eff,
  ) {
    var coreWorse = 0;
    var effWorse = 0;
    var similar = 0;
    for (var i = 0; i < core.length; i++) {
      final c = (core[i]['minJ'] as num).toDouble();
      final e = (eff[i]['minJ'] as num).toDouble();
      if ((c - e).abs() < 0.02) {
        similar++;
      } else if (c < e) {
        coreWorse++;
      } else {
        effWorse++;
      }
    }
    if (coreWorse > effWorse && coreWorse > similar) {
      return 'support_reduces_fold';
    }
    if (effWorse > coreWorse) {
      return 'support_worsens_or_neutral_fold';
    }
    return 'support_minimal_effect';
  }

  static String _rootComponentReport() =>
      'PilotWarpDisplacement._faceSlim: horizontal Offset(shiftX,0) toward faceCenterX; '
      'effectiveMag=pow(intensity,1.35); maxPx=0.08*fse*effectiveMag; '
      'edgeWeight=pow(lateral/halfFace,0.72); zoneWeight attenuates ny<0.40 and ny>0.66; '
      'primaryZones=cheek/jaw/temple/skullContour per FaceToolSpecification.face_slim';

  static String _pipelineReport() =>
      'FaceMeshDeformationEngine.composeVertexField → AnatomicalIntentFactory.build → '
      'AnatomicalConstraintEngine.compose → PilotWarpDisplacement.deltaFor(face_slim) → '
      'GeometricSupport.computeWeights → FaceWarpFieldMetrics.effectiveDelta';

  static ({
    Map<String, dynamic> stats,
    _JSample? minSample,
    List<_JSample> hotspots,
  }) _scanJacobianField({
    required TriMeshSpatialIndex sourceIndex,
    required dynamic vf,
    required Float32List supportWeights,
    required int vertexCount,
    required ({int x0, int y0, int x1, int y1}) roi,
    required bool useCoreOnly,
  }) {
    const gridStep = 4.0;
    const h = 2.0;
    final jValues = <double>[];
    _JSample? minSample;
    final hotspots = <_JSample>[];

    for (var y = roi.y0 + gridStep; y <= roi.y1 - gridStep; y += gridStep) {
      for (var x = roi.x0 + gridStep; x <= roi.x1 - gridStep; x += gridStep) {
        final r = _jacobianDetailedAt(
          sourceIndex: sourceIndex,
          vf: vf,
          supportWeights: supportWeights,
          vertexCount: vertexCount,
          px: x + 0.5,
          py: y + 0.5,
          h: h,
          useCoreOnly: useCoreOnly,
        );
        if (r == null) {
          continue;
        }
        jValues.add(r.j);
        if (minSample == null || r.j < minSample.j) {
          minSample = r;
        }
        if (r.j <= 0) {
          hotspots.add(r);
        }
      }
    }

    jValues.sort();
    return (
      stats: {
        'minJ': jValues.isEmpty ? 0.0 : jValues.first,
        'p01J': _percentile(jValues, 0.01),
        'p05J': _percentile(jValues, 0.05),
        'medianJ': _percentile(jValues, 0.5),
        'hotspotCountLeZero': hotspots.length,
      },
      minSample: minSample,
      hotspots: hotspots,
    );
  }

  static _JSample? _jacobianDetailedAt({
    required TriMeshSpatialIndex sourceIndex,
    required dynamic vf,
    required Float32List supportWeights,
    required int vertexCount,
    required double px,
    required double py,
    required double h,
    required bool useCoreOnly,
  }) {
    Offset? disp(double x, double y) {
      final tri = sourceIndex.locateTriangleIndex(x, y);
      if (tri == null) {
        return null;
      }
      final hit = sourceIndex.barycentricInTriangle(tri, x, y);
      if (hit == null) {
        return null;
      }
      var dx = 0.0;
      var dy = 0.0;
      for (final (i, w) in [
        (hit.i0, hit.w0),
        (hit.i1, hit.w1),
        (hit.i2, hit.w2),
      ]) {
        if (i >= vertexCount) {
          return null;
        }
        final core = vf.displacementAt(i);
        final delta = useCoreOnly
            ? core
            : FaceWarpFieldMetrics.effectiveDelta(
                core,
                supportWeights[i].clamp(0.0, 1.0),
              );
        dx += w * delta.dx;
        dy += w * delta.dy;
      }
      return Offset(dx, dy);
    }

    final c = disp(px, py);
    final xp = disp(px + h, py);
    final xm = disp(px - h, py);
    final yp = disp(px, py + h);
    final ym = disp(px, py - h);
    if (c == null || xp == null || xm == null || yp == null || ym == null) {
      return null;
    }

    final dudx = (xp.dx - xm.dx) / (2 * h);
    final dudy = (yp.dx - ym.dx) / (2 * h);
    final dvdx = (xp.dy - xm.dy) / (2 * h);
    final dvdy = (yp.dy - ym.dy) / (2 * h);
    final j = (1 + dudx) * (1 + dvdy) - dudy * dvdx;

    return _JSample(
      px: px,
      py: py,
      j: j,
      gradDx: dudx,
      gradDy: dvdx,
      onePlusDdxDx: 1 + dudx,
    );
  }

  static List<Map<String, dynamic>> _checkMonotonicity({
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required dynamic vf,
    required Float32List supportWeights,
    required List<Set<int>> neighbors,
    required int vertexCount,
    required double intensity,
    required Map<int, String> zoneLookup,
  }) {
    final violations = <Map<String, dynamic>>[];
    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);
    final faceSlimZones = FaceModelSpecification.toolSpecifications['face_slim']!
        .primaryZones;

    final lateral = List<double>.filled(vertexCount, 0);
    final mag = List<double>.filled(vertexCount, 0);
    for (var i = 0; i < vertexCount; i++) {
      lateral[i] = (mesh.vertices[i * 2] - centerX).abs();
      final core = vf.displacementAt(i);
      final eff = FaceWarpFieldMetrics.effectiveDelta(
        core,
        supportWeights[i].clamp(0.0, 1.0),
      );
      mag[i] = eff.distance;
    }

    for (var i = 0; i < vertexCount; i++) {
      final zone = zoneLookup[i];
      if (zone == null || !faceSlimZones.any((z) => z.name == zone)) {
        continue;
      }
      for (final j in neighbors[i]) {
        if (j >= vertexCount) {
          continue;
        }
        if (lateral[i] < lateral[j] && mag[i] > mag[j] + 0.5) {
          violations.add({
            'faceSlim': intensity,
            'interiorVertex': i,
            'exteriorVertex': j,
            'interiorLateral': lateral[i],
            'exteriorLateral': lateral[j],
            'interiorMag': mag[i],
            'exteriorMag': mag[j],
            'zone': zone,
          });
        }
      }
    }
    return violations;
  }

  static Future<void> _writeVectorFieldPng({
    required String outDir,
    required FaceMeshResult face,
    required TriMesh mesh,
    required InfluenceMap influence,
    required PersonMask? personMask,
    required int width,
    required int height,
    required double intensity,
    required FaceMeshDeformationEngine engine,
    required Size imageSize,
    required TriMeshSpatialIndex sourceIndex,
  }) async {
    final label = (intensity * 100).round();
    final vf = engine.composeVertexField(
      parameters: {'face_slim': intensity},
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
    );
    final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
      field: vf,
      mesh: mesh,
    );
    final sw = GeometricSupport.computeWeights(
      mesh: mesh,
      coreField: vf,
      influenceMap: influence,
      params: const DeformationSupportParams(),
      imageWidth: width,
      imageHeight: height,
      personMask: personMask,
    );

    final jScan = _scanJacobianField(
      sourceIndex: sourceIndex,
      vf: vf,
      supportWeights: sw,
      vertexCount: vertexCount,
      roi: _roiFromMesh(mesh, width, height),
      useCoreOnly: false,
    );
    final foldPts = jScan.hotspots.take(200);

    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(16, 16, 20));

    for (final hs in foldPts) {
      final ix = hs.px.round().clamp(0, width - 1);
      final iy = hs.py.round().clamp(0, height - 1);
      for (var dy = -3; dy <= 3; dy++) {
        for (var dx = -3; dx <= 3; dx++) {
          final x = ix + dx;
          final y = iy + dy;
          if (x >= 0 && y >= 0 && x < width && y < height) {
            image.setPixelRgb(x, y, 80, 20, 20);
          }
        }
      }
    }

    for (var i = 0; i < vertexCount; i += 3) {
      final sx = mesh.vertices[i * 2];
      final sy = mesh.vertices[i * 2 + 1];
      if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
        continue;
      }
      final core = vf.displacementAt(i);
      if (core.distance < 0.1) {
        continue;
      }
      final eff = FaceWarpFieldMetrics.effectiveDelta(core, sw[i].clamp(0, 1));
      final x0 = sx.round();
      final y0 = sy.round();
      final x1 = (sx + eff.dx).round();
      final y1 = (sy + eff.dy).round();
      _drawLine(image, x0, y0, x1, y1, 80, 200, 255);
      image.setPixelRgb(x0, y0, 255, 255, 255);
    }

    File('$outDir/debug-face-slim-vector-field-$label.png')
        .writeAsBytesSync(img.encodePng(image));
  }

  static Future<void> _writeCompressionPng({
    required String outDir,
    required FaceMeshResult face,
    required TriMesh mesh,
    required InfluenceMap influence,
    required PersonMask? personMask,
    required int width,
    required int height,
    required double intensity,
    required FaceMeshDeformationEngine engine,
    required Size imageSize,
    required List<(int, int)> edges,
  }) async {
    final label = (intensity * 100).round();
    final vf = engine.composeVertexField(
      parameters: {'face_slim': intensity},
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
    );
    final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
      field: vf,
      mesh: mesh,
    );
    final sw = GeometricSupport.computeWeights(
      mesh: mesh,
      coreField: vf,
      influenceMap: influence,
      params: const DeformationSupportParams(),
      imageWidth: width,
      imageHeight: height,
      personMask: personMask,
    );
    final deformed = _deformedVertices(
      mesh: mesh,
      vf: vf,
      supportWeights: sw,
      vertexCount: vertexCount,
    );

    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(20, 20, 24));

    for (final (i, j) in edges) {
      if (i >= vertexCount || j >= vertexCount) {
        continue;
      }
      final ds = _dist(mesh.vertices, i, j);
      if (ds < 1e-3) {
        continue;
      }
      final ratio = (_dist(deformed, i, j) / ds).clamp(0.0, 1.0);
      final mx = ((mesh.vertices[i * 2] + mesh.vertices[j * 2]) / 2).round();
      final my =
          ((mesh.vertices[i * 2 + 1] + mesh.vertices[j * 2 + 1]) / 2).round();
      if (mx < 0 || my < 0 || mx >= width || my >= height) {
        continue;
      }
      final r = ratio <= 0.25
          ? 255
          : ratio <= 0.5
              ? 255
              : (255 * (1 - ratio)).round();
      final g = ratio <= 0.25
          ? 40
          : ratio <= 0.5
              ? 180
              : (180 * ratio).round();
      final b = 40;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final x = mx + dx;
          final y = my + dy;
          if (x >= 0 && y >= 0 && x < width && y < height) {
            image.setPixelRgb(x, y, r, g, b);
          }
        }
      }
    }

    File('$outDir/debug-face-slim-compression-$label.png')
        .writeAsBytesSync(img.encodePng(image));
  }

  static Float32List _deformedVertices({
    required TriMesh mesh,
    required dynamic vf,
    required Float32List supportWeights,
    required int vertexCount,
  }) {
    final out = Float32List.fromList(mesh.vertices);
    for (var i = 0; i < vertexCount; i++) {
      final eff = FaceWarpFieldMetrics.effectiveDelta(
        vf.displacementAt(i),
        supportWeights[i].clamp(0.0, 1.0),
      );
      out[i * 2] += eff.dx;
      out[i * 2 + 1] += eff.dy;
    }
    return out;
  }

  static Map<int, String> _buildVertexZoneLookup() {
    final map = <int, String>{};
    for (final entry in VertexRoleMap.zoneLandmarks.entries) {
      for (final idx in entry.value) {
        map[idx] = entry.key.name;
      }
    }
    return map;
  }

  static String _dominantRegion(List<Map<String, dynamic>> verts) {
    final counts = <String, int>{};
    for (final v in verts) {
      final z = v['anatomicalZone'] as String? ?? 'unknown';
      counts[z] = (counts[z] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return 'unknown';
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static List<Set<int>> _buildVertexNeighbors(TriMesh mesh) {
    final n = mesh.vertices.length ~/ 2;
    final neighbors = List.generate(n, (_) => <int>{});
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 < n && i1 < n && i2 < n) {
        neighbors[i0].addAll([i1, i2]);
        neighbors[i1].addAll([i0, i2]);
        neighbors[i2].addAll([i0, i1]);
      }
    }
    return neighbors;
  }

  static List<(int, int)> _buildUniqueEdges(TriMesh mesh) {
    final set = <String, (int, int)>{};
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      for (final (a, b) in [(i0, i1), (i1, i2), (i2, i0)]) {
        final lo = a < b ? a : b;
        final hi = a < b ? b : a;
        set['$lo-$hi'] = (lo, hi);
      }
    }
    return set.values.toList();
  }

  static double _dist(Float32List verts, int a, int b) {
    final dx = verts[a * 2] - verts[b * 2];
    final dy = verts[a * 2 + 1] - verts[b * 2 + 1];
    return math.sqrt(dx * dx + dy * dy);
  }

  static bool _orderSwapHorizontal(
    Float32List src,
    Float32List dst,
    int a,
    int b,
  ) {
    final sxA = src[a * 2];
    final sxB = src[b * 2];
    final dxA = dst[a * 2];
    final dxB = dst[b * 2];
    return (sxA - sxB).sign != (dxA - dxB).sign;
  }

  static void _drawLine(
    img.Image image,
    int x0,
    int y0,
    int x1,
    int y1,
    int r,
    int g,
    int b,
  ) {
    final steps = math.max((x1 - x0).abs(), (y1 - y0).abs());
    if (steps == 0) {
      return;
    }
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x0 + (x1 - x0) * t).round();
      final y = (y0 + (y1 - y0) * t).round();
      if (x >= 0 && y >= 0 && x < image.width && y < image.height) {
        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }

  static ({
    int x0,
    int y0,
    int x1,
    int y1,
  }) _roiFromMesh(
    TriMesh mesh,
    int width,
    int height,
  ) {
    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;
    for (var i = 0; i < mesh.vertices.length; i += 2) {
      minX = math.min(minX, mesh.vertices[i].floor());
      minY = math.min(minY, mesh.vertices[i + 1].floor());
      maxX = math.max(maxX, mesh.vertices[i].ceil());
      maxY = math.max(maxY, mesh.vertices[i + 1].ceil());
    }
    const margin = 3;
    return (
      x0: (minX - margin).clamp(0, width - 1),
      y0: (minY - margin).clamp(0, height - 1),
      x1: (maxX + margin).clamp(0, width - 1),
      y1: (maxY + margin).clamp(0, height - 1),
    );
  }

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) {
      return 0.0;
    }
    final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}

class _JSample {
  const _JSample({
    required this.px,
    required this.py,
    required this.j,
    required this.gradDx,
    required this.gradDy,
    required this.onePlusDdxDx,
  });

  final double px;
  final double py;
  final double j;
  final double gradDx;
  final double gradDy;
  final double onePlusDdxDx;
}

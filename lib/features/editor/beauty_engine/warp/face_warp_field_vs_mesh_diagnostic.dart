import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;

import '../body_reshape/maps/influence_map.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/face_mesh_result.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/face_matte_roi.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'experimental/jacobian_safe_constraint.dart';
import 'experimental/triangle_jacobian_math.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

/// Fase 9 — diagnóstico field J vs mesh J (obrigatório antes do solver global).
abstract final class FaceWarpFieldVsMeshDiagnostic {
  FaceWarpFieldVsMeshDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _watchTriangles = [
    151, 153, 331, 394, 411, 547, 549, 723, 724, 725, 786, 149,
  ];

  static Future<Map<String, dynamic>?> run({
    required FaceMeshResult face,
    required TriMesh mesh,
    required int width,
    required int height,
    PersonMask? personMask,
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

      final configs = <Map<String, dynamic>>[];

      for (final spec in [
        (label: 'BASELINE', intensity: 0.9, phase8: false),
        (label: 'PHASE8_J010', intensity: 0.9, phase8: true),
      ]) {
        debugPrint('P9 field-vs-mesh ${spec.label}');

        final built = _buildPipeline(
          engine: engine,
          face: face,
          mesh: mesh,
          imageSize: imageSize,
          influence: influence,
          personMask: personMask,
          width: width,
          height: height,
          intensity: spec.intensity,
        );

        var deltas = built.effectiveDeltas;
        if (spec.phase8) {
          deltas = JacobianSafeConstraint.apply(
            mesh: mesh,
            effectiveDeltas: built.effectiveDeltas,
            epsilon: 0.10,
            enabled: true,
          ).constrainedDeltas;
        }

        final analysis = _analyzeFieldVsMesh(
          mesh: mesh,
          deltas: deltas,
          sourceIndex: sourceIndex,
          vertexCount: built.vertexCount,
        );

        configs.add({
          'config': spec.label,
          'faceSlim': spec.intensity,
          ...analysis,
        });
      }

      final report = {
        'definitions': {
          'fieldJ_finiteDiff':
              'J = (1+∂u/∂x)(1+∂v/∂y) - ∂u/∂y·∂v/∂x via diferenças finitas h=2px no campo PL interpolado',
          'fieldJ_exactPL':
              'J = det(F) no centróide = mesh J (constante dentro do triângulo)',
          'meshJ':
              'J = det(F) do mapa afim source→destination por triângulo',
          'horizontalNote':
              'Com dy=0: det(F) = 1 + ∂u/∂x exatamente; field FD pode divergir perto de arestas ou cruzando triângulos',
        },
        'divergenceExplanation': _buildExplanation(configs),
        'configs': configs,
        'watchedTriangles': _watchTriangles,
      };

      final path = '$outDir/phase9_field_vs_mesh.json';
      File(path).writeAsStringSync(jsonEncode(report));
      debugPrint('P9 field-vs-mesh written: $path');
      return report;
    } catch (e, st) {
      debugPrint('P9 field-vs-mesh FAIL $e\n$st');
      return null;
    }
  }

  static Map<String, dynamic> _analyzeFieldVsMesh({
    required TriMesh mesh,
    required List<Offset> deltas,
    required TriMeshSpatialIndex sourceIndex,
    required int vertexCount,
  }) {
    final perTriangle = <Map<String, dynamic>>[];
    var agreeCount = 0;
    var divergeCount = 0;
    var maxAbsDiff = 0.0;
    var maxDiffTri = -1;

    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 >= vertexCount || i1 >= vertexCount || i2 >= vertexCount) {
        continue;
      }

      final meshJ = TriangleJacobianMath.meshTriangleJacobian(
        mesh,
        deltas,
        i0,
        i1,
        i2,
      );
      final exactFieldJ =
          TriangleJacobianMath.exactFieldJacobianAtCentroid(mesh, deltas, t);
      final horizJ =
          TriangleJacobianMath.horizontalFieldJacobianExact(mesh, deltas, t);

      final centroid = TriangleJacobianMath.triangleCentroid(mesh, t);
      final fdJ = TriangleJacobianMath.finiteDiffFieldJacobian(
        sourceIndex: sourceIndex,
        deltas: deltas,
        vertexCount: vertexCount,
        px: centroid.cx,
        py: centroid.cy,
      );

      final srcArea =
          TriangleJacobianMath.signedTriangleArea(mesh, deltas, t).abs();
      final dstArea = TriangleJacobianMath.signedTriangleArea(
        mesh,
        deltas,
        t,
        destination: true,
      ).abs();
      final areaRatio = srcArea > 1e-12 ? dstArea / srcArea : 0.0;

      final exactDiff = (meshJ - exactFieldJ).abs();
      final fdDiff = fdJ == null ? null : (meshJ - fdJ).abs();
      final horizDiff = (meshJ - horizJ).abs();

      if (exactDiff < 1e-6) {
        agreeCount++;
      } else {
        divergeCount++;
      }

      if (exactDiff > maxAbsDiff) {
        maxAbsDiff = exactDiff;
        maxDiffTri = t;
      }

      final meshFold = meshJ < 0;
      final exactFieldFold = exactFieldJ < 0;
      final fdFieldFold = fdJ != null && fdJ < 0;

      perTriangle.add({
        'triangleId': t,
        'vertices': [i0, i1, i2],
        'sourceArea': srcArea,
        'destinationArea': dstArea,
        'areaRatio': areaRatio,
        'meshJ': meshJ,
        'exactFieldJ': exactFieldJ,
        'horizontalExactJ': horizJ,
        'finiteDiffFieldJ': fdJ,
        'meshJ_vs_exactFieldJ': exactDiff,
        'meshJ_vs_finiteDiff': fdDiff,
        'meshJ_vs_horizontal': horizDiff,
        'meshFold': meshFold,
        'exactFieldFold': exactFieldFold,
        'finiteDiffFieldFold': fdFieldFold,
        'classification': _classify(meshJ, exactFieldJ, fdJ),
        'centroid': {'x': centroid.cx, 'y': centroid.cy},
        'deltas': [
          {'v': i0, 'dx': deltas[i0].dx, 'dy': deltas[i0].dy},
          {'v': i1, 'dx': deltas[i1].dx, 'dy': deltas[i1].dy},
          {'v': i2, 'dx': deltas[i2].dx, 'dy': deltas[i2].dy},
        ],
      });
    }

    perTriangle.sort(
      (a, b) => (b['meshJ_vs_finiteDiff'] as num? ?? 0)
          .compareTo(a['meshJ_vs_finiteDiff'] as num? ?? 0),
    );

    final meshJs = TriangleJacobianMath.allMeshJacobians(mesh, deltas);
    final fdJs = <double>[];
    for (var t = 0; t < mesh.triangleCount; t++) {
      final c = TriangleJacobianMath.triangleCentroid(mesh, t);
      final j = TriangleJacobianMath.finiteDiffFieldJacobian(
        sourceIndex: sourceIndex,
        deltas: deltas,
        vertexCount: vertexCount,
        px: c.cx,
        py: c.cy,
      );
      if (j != null) {
        fdJs.add(j);
      }
    }
    fdJs.sort();

    final watched = perTriangle
        .where((r) => _watchTriangles.contains(r['triangleId']))
        .toList();

    final meshFoldTris =
        perTriangle.where((r) => r['meshFold'] == true).toList();
    final fdFoldButMeshOk = perTriangle
        .where(
          (r) =>
              r['meshFold'] == false &&
              r['finiteDiffFieldFold'] == true,
        )
        .toList();
    final meshFoldButFdOk = perTriangle
        .where(
          (r) =>
              r['meshFold'] == true &&
              r['finiteDiffFieldFold'] == false,
        )
        .toList();

    return {
      'minMeshJ': TriangleJacobianMath.minJacobian(meshJs),
      'minExactFieldJ': TriangleJacobianMath.minJacobian(
        perTriangle.map((r) => r['exactFieldJ'] as double).toList(),
      ),
      'minFiniteDiffFieldJ': fdJs.isEmpty ? 1.0 : fdJs.first,
      'meshFoldCount': TriangleJacobianMath.countBelow(meshJs, 0),
      'exactFieldFoldCount': perTriangle
          .where((r) => r['exactFieldFold'] == true)
          .length,
      'finiteDiffFieldFoldCount_atCentroids': perTriangle
          .where((r) => r['finiteDiffFieldFold'] == true)
          .length,
      'exactAgreeCount': agreeCount,
      'exactDivergeCount': divergeCount,
      'maxExactDiff': maxAbsDiff,
      'maxExactDiffTriangle': maxDiffTri,
      'meshFoldTriangles': meshFoldTris.take(30).toList(),
      'fdFoldButMeshOk': fdFoldButMeshOk.take(20).toList(),
      'meshFoldButFdOk': meshFoldButFdOk.take(20).toList(),
      'topFiniteDiffDivergence': perTriangle.take(30).toList(),
      'watchedTrianglesDetail': watched,
    };
  }

  static String _classify(double meshJ, double exactJ, double? fdJ) {
    if (meshJ < 0 && exactJ < 0) {
      if (fdJ != null && fdJ >= 0) {
        return 'both_fold_fd_underestimates';
      }
      return 'both_fold_agree';
    }
    if (meshJ >= 0 && exactJ >= 0) {
      if (fdJ != null && fdJ < 0) {
        return 'both_ok_fd_overestimates_fold';
      }
      return 'both_ok';
    }
    return 'mesh_exact_mismatch';
  }

  static Map<String, dynamic> _buildExplanation(
    List<Map<String, dynamic>> configs,
  ) {
    final baseline = configs.firstWhere((c) => c['config'] == 'BASELINE');
    final phase8 = configs.firstWhere((c) => c['config'] == 'PHASE8_J010');

    return {
      'exactVsMesh':
          'mesh J e exact field J (det F no centróide) são idênticos por construção PL; divergência numérica ~0',
      'finiteDiffVsMesh':
          'FD h=2px no centróide pode divergir de mesh J perto de arestas ou quando stencil cruza fronteira de triângulo',
      'phase8Gap': {
        'baseline_meshFoldCount': baseline['meshFoldCount'],
        'phase8_meshFoldCount': phase8['meshFoldCount'],
        'phase8_fdFoldAtCentroids': phase8['finiteDiffFieldFoldCount_atCentroids'],
        'phase8_minMeshJ': phase8['minMeshJ'],
        'phase8_minFiniteDiff': phase8['minFiniteDiffFieldJ'],
        'cause':
            'Fase 8 usa iteração local Gauss-Seidel (ordem-dependent) com max 8 passagens; vértices compartilhados recebem min(scale) sem convergência global → triângulos vizinhos permanecem invertidos enquanto FD no grid pode ficar ≥0',
      },
      'gridScanVsPerTriangle': {
        'note':
            'foldCount de campo (Fase 8) usa scan de grid 4px com FD; minJ de grid pode ser > minJ mesh porque piores triângulos não coincidem com amostras do grid ou FD subestima fold no centróide',
      },
    };
  }

  static ({
    dynamic vertexField,
    List<Offset> effectiveDeltas,
    Float32List supportWeights,
    int vertexCount,
  }) _buildPipeline({
    required FaceMeshDeformationEngine engine,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required InfluenceMap influence,
    required PersonMask? personMask,
    required int width,
    required int height,
    required double intensity,
  }) {
    final vertexField = engine.composeVertexField(
      parameters: {'face_slim': intensity},
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
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
    final effectiveDeltas = List<Offset>.generate(
      vertexCount,
      (i) => FaceWarpFieldMetrics.effectiveDelta(
        vertexField.displacementAt(i),
        supportWeights[i].clamp(0.0, 1.0),
      ),
    );
    return (
      vertexField: vertexField,
      effectiveDeltas: effectiveDeltas,
      supportWeights: supportWeights,
      vertexCount: vertexCount,
    );
  }
}

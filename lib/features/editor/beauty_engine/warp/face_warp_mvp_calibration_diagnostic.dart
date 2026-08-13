import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;
import 'package:image/image.dart' as img;

import '../body_reshape/maps/influence_map.dart';
import '../filters/face/face_warp_utils.dart';
import '../models/face_mesh_result.dart';
import '../models/tri_mesh.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/anatomical_intent_factory.dart';
import 'anatomy/anatomical_zone.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'anatomy/face_matte_roi.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'anatomy/face_model_specification.dart';
import 'anatomy/pilot_warp_displacement.dart';
import 'anatomy/vertex_role_map.dart';
import 'face_warp_mvp_operations.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;
import 'face_warp_structural_pipeline.dart';

/// Métricas de um estágio do pipeline para uma ferramenta/intensidade.
class MvpStageMetrics {
  const MvpStageMetrics({
    required this.stage,
    required this.movedVertexCount,
    required this.maxDisplacementPx,
    required this.meanDisplacementPx,
    required this.roiMaxDisplacementPx,
    required this.roiMeanDisplacementPx,
    required this.roiMovedVertexCount,
  });

  final String stage;
  final int movedVertexCount;
  final double maxDisplacementPx;
  final double meanDisplacementPx;
  final double roiMaxDisplacementPx;
  final double roiMeanDisplacementPx;
  final int roiMovedVertexCount;

  Map<String, dynamic> toJson() => {
        'stage': stage,
        'movedVertexCount': movedVertexCount,
        'maxDisplacementPx': maxDisplacementPx,
        'meanDisplacementPx': meanDisplacementPx,
        'roiMaxDisplacementPx': roiMaxDisplacementPx,
        'roiMeanDisplacementPx': roiMeanDisplacementPx,
        'roiMovedVertexCount': roiMovedVertexCount,
      };
}

/// Curva de slider + gargalo identificado.
class MvpToolIntensityReport {
  const MvpToolIntensityReport({
    required this.intensity,
    required this.generator,
    required this.ace,
    required this.phase9,
    required this.effective,
    required this.phase9RetentionFromAce,
    required this.effectiveRetentionFromPhase9,
    required this.aceRetentionFromGenerator,
  });

  final double intensity;
  final MvpStageMetrics generator;
  final MvpStageMetrics ace;
  final MvpStageMetrics phase9;
  final MvpStageMetrics effective;
  final double phase9RetentionFromAce;
  final double effectiveRetentionFromPhase9;
  final double aceRetentionFromGenerator;

  Map<String, dynamic> toJson() => {
        'intensity': intensity,
        'generator': generator.toJson(),
        'ace': ace.toJson(),
        'phase9': phase9.toJson(),
        'effective': effective.toJson(),
        'phase9RetentionFromAce': phase9RetentionFromAce,
        'effectiveRetentionFromPhase9': effectiveRetentionFromPhase9,
        'aceRetentionFromGenerator': aceRetentionFromGenerator,
      };
}

/// Relatório completo de uma ferramenta MVP.
class MvpToolCalibrationReport {
  const MvpToolCalibrationReport({
    required this.toolKey,
    required this.primaryRoi,
    required this.primaryRoiVertexCount,
    required this.intensityReports,
    required this.primaryBottleneck,
    required this.bottleneckDetail,
    required this.heatmapPath,
    required this.generatorRecommendation,
  });

  final String toolKey;
  final String primaryRoi;
  final int primaryRoiVertexCount;
  final List<MvpToolIntensityReport> intensityReports;
  final String primaryBottleneck;
  final String bottleneckDetail;
  final String heatmapPath;
  final String generatorRecommendation;

  Map<String, dynamic> toJson() => {
        'toolKey': toolKey,
        'primaryRoi': primaryRoi,
        'primaryRoiVertexCount': primaryRoiVertexCount,
        'intensityReports': intensityReports.map((r) => r.toJson()).toList(),
        'primaryBottleneck': primaryBottleneck,
        'bottleneckDetail': bottleneckDetail,
        'heatmapPath': heatmapPath,
        'generatorRecommendation': generatorRecommendation,
      };
}

/// Etapa 1 — diagnóstico de calibração MVP (sem alterar produção).
abstract final class FaceWarpMvpCalibrationDiagnostic {
  FaceWarpMvpCalibrationDiagnostic._();

  static const defaultIntensities = [0.2, 0.5, 0.8, 1.0];
  static const _moveThresholdPx = 0.05;
  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor/mvp-calibration-stage1';

  static const _foreheadLowerIndices = {297, 332, 109, 67, 103, 54, 21};

  static Future<Map<String, dynamic>> run({
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    List<double> intensities = defaultIntensities,
    String? outputDirectory,
    String runId = 'mvp-calib-stage1',
    List<String>? toolKeysFilter,
    bool writeHeatmaps = true,
  }) async {
    final outDir = outputDirectory ?? _defaultOutputDir;
    Directory(outDir).createSync(recursive: true);

    const engine = FaceMeshDeformationEngine();

    final influence = FaceMatteRoi.buildInfluenceMap(
      face: face,
      imageSize: imageSize,
      lateralRadiusExpand: 0.07,
    );

    final toolReports = <MvpToolCalibrationReport>[];
    final keys = _resolveToolKeys(toolKeysFilter);

    for (final toolKey in keys) {
      final roiIndices = _roiIndicesFor(toolKey);
      final intensityReports = <MvpToolIntensityReport>[];

      ConstrainedVertexField? heatmapField;

      for (final intensity in intensities) {
        final params = {toolKey: intensity};
        final context = FaceAnatomyContext(
          face: face,
          imageSize: imageSize,
          mesh: mesh,
        );

        final generatorField = _composeGeneratorField(
          parameters: params,
          context: context,
        );
        final aceField = engine.composeVertexField(
          parameters: params,
          context: context,
          mesh: mesh,
          applyStructuralPipeline: false,
        );
        final phase9Result = FaceWarpStructuralPipeline.apply(
          mesh: mesh,
          inputField: aceField,
        );
        final phase9Field = phase9Result.vertexField;

        final supportWeights = GeometricSupport.computeWeights(
          mesh: mesh,
          coreField: phase9Field,
          influenceMap: influence,
          params: const DeformationSupportParams(),
          imageWidth: imageSize.width.round(),
          imageHeight: imageSize.height.round(),
        );
        final effectiveField = _applySupportWeights(
          field: phase9Field,
          mesh: mesh,
          supportWeights: supportWeights,
        );

        final genM = _metricsFor(
          stage: 'generator',
          field: generatorField,
          mesh: mesh,
          roiIndices: roiIndices,
        );
        final aceM = _metricsFor(
          stage: 'ace',
          field: aceField,
          mesh: mesh,
          roiIndices: roiIndices,
        );
        final p9M = _metricsFor(
          stage: 'phase9',
          field: phase9Field,
          mesh: mesh,
          roiIndices: roiIndices,
        );
        final effM = _metricsFor(
          stage: 'effective',
          field: effectiveField,
          mesh: mesh,
          roiIndices: roiIndices,
        );

        intensityReports.add(
          MvpToolIntensityReport(
            intensity: intensity,
            generator: genM,
            ace: aceM,
            phase9: p9M,
            effective: effM,
            aceRetentionFromGenerator: _retention(
              genM.roiMaxDisplacementPx,
              aceM.roiMaxDisplacementPx,
            ),
            phase9RetentionFromAce: _retention(
              aceM.roiMaxDisplacementPx,
              p9M.roiMaxDisplacementPx,
            ),
            effectiveRetentionFromPhase9: _retention(
              p9M.roiMaxDisplacementPx,
              effM.roiMaxDisplacementPx,
            ),
          ),
        );

        if (intensity == 1.0) {
          heatmapField = phase9Field;
        }
      }

      final at100 = intensityReports.last;
      final bottleneck = _identifyBottleneck(at100);

      final heatmapPath = writeHeatmaps
          ? '$outDir/heatmap-$toolKey-i1.0.png'
          : '';
      if (writeHeatmaps) {
        _writeDisplacementHeatmap(
          mesh: mesh,
          field: heatmapField!,
          imageWidth: imageSize.width.round(),
          imageHeight: imageSize.height.round(),
          outputPath: heatmapPath,
          roiIndices: roiIndices,
        );
      }

      final report = MvpToolCalibrationReport(
        toolKey: toolKey,
        primaryRoi: _roiLabel(toolKey),
        primaryRoiVertexCount: roiIndices.length,
        intensityReports: intensityReports,
        primaryBottleneck: bottleneck.$1,
        bottleneckDetail: bottleneck.$2,
        heatmapPath: heatmapPath,
        generatorRecommendation: '', // patched below
      );

      toolReports.add(report);
    }

    // Second pass: recommendations referencing face_slim @1.0 effective ROI max.
    final faceSlimReport = toolReports
        .where((r) => r.toolKey == 'face_slim')
        .toList();
    final faceSlimEffectiveMax = faceSlimReport.isNotEmpty
        ? faceSlimReport.first.intensityReports.last.effective
            .roiMaxDisplacementPx
        : _faceSlimReferenceMax(
            face: face,
            mesh: mesh,
            imageSize: imageSize,
            engine: engine,
            influence: influence,
          );

    final patchedReports = toolReports.map((r) {
      if (r.toolKey == 'face_slim') {
        return MvpToolCalibrationReport(
          toolKey: r.toolKey,
          primaryRoi: r.primaryRoi,
          primaryRoiVertexCount: r.primaryRoiVertexCount,
          intensityReports: r.intensityReports,
          primaryBottleneck: r.primaryBottleneck,
          bottleneckDetail: r.bottleneckDetail,
          heatmapPath: r.heatmapPath,
          generatorRecommendation:
              'Referência perceptual — effective ROI max @1.0 = '
              '${faceSlimEffectiveMax.toStringAsFixed(2)} px',
        );
      }
      final at100 = r.intensityReports.last;
      final rec = _generatorRecommendation(
        toolKey: r.toolKey,
        report: at100,
        bottleneck: (r.primaryBottleneck, r.bottleneckDetail),
        faceSlimEffectiveMax: faceSlimEffectiveMax,
      );
      return MvpToolCalibrationReport(
        toolKey: r.toolKey,
        primaryRoi: r.primaryRoi,
        primaryRoiVertexCount: r.primaryRoiVertexCount,
        intensityReports: r.intensityReports,
        primaryBottleneck: r.primaryBottleneck,
        bottleneckDetail: r.bottleneckDetail,
        heatmapPath: r.heatmapPath,
        generatorRecommendation: rec,
      );
    }).toList();

    final summary = {
      'runId': runId,
      'imageSize': {'width': imageSize.width, 'height': imageSize.height},
      'intensities': intensities,
      'faceSlimReferenceEffectiveRoiMaxPx': faceSlimEffectiveMax,
      'tools': patchedReports.map((r) => r.toJson()).toList(),
    };

    final jsonPath = '$outDir/mvp-calibration-stage1-summary.json';
    File(jsonPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
    );

    final mdPath = '$outDir/mvp-calibration-stage1-report.md';
    File(mdPath).writeAsStringSync(_markdownReport(summary, patchedReports));

    return summary;
  }

  static List<String> _resolveToolKeys(List<String>? filter) {
    if (filter == null || filter.isEmpty) {
      return FaceWarpMvpOperations.parameterKeys.toList();
    }
    final out = <String>{...filter};
    if (!out.contains('face_slim')) {
      out.add('face_slim');
    }
    return FaceWarpMvpOperations.parameterKeys.where(out.contains).toList();
  }

  static double _faceSlimReferenceMax({
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required FaceMeshDeformationEngine engine,
    required InfluenceMap influence,
  }) {
    const intensity = 1.0;
    const toolKey = 'face_slim';
    final roiIndices = _roiIndicesFor(toolKey);
    final params = {toolKey: intensity};
    final context = FaceAnatomyContext(
      face: face,
      imageSize: imageSize,
      mesh: mesh,
    );
    final aceField = engine.composeVertexField(
      parameters: params,
      context: context,
      mesh: mesh,
      applyStructuralPipeline: false,
    );
    final phase9Field = FaceWarpStructuralPipeline.apply(
      mesh: mesh,
      inputField: aceField,
    ).vertexField;
    final supportWeights = GeometricSupport.computeWeights(
      mesh: mesh,
      coreField: phase9Field,
      influenceMap: influence,
      params: const DeformationSupportParams(),
      imageWidth: imageSize.width.round(),
      imageHeight: imageSize.height.round(),
    );
    final effectiveField = _applySupportWeights(
      field: phase9Field,
      mesh: mesh,
      supportWeights: supportWeights,
    );
    return _metricsFor(
      stage: 'effective',
      field: effectiveField,
      mesh: mesh,
      roiIndices: roiIndices,
    ).roiMaxDisplacementPx;
  }

  /// Campo generator-only: pilot deltas + semiRigid, sem clamp/rigid/antiFold.
  static ConstrainedVertexField _composeGeneratorField({
    required Map<String, double> parameters,
    required FaceAnatomyContext context,
  }) {
    const semiRigidWeight = 0.5;
    const count = FaceMeshResult.expectedLandmarkCount;
    final dx = Float32List(count);
    final dy = Float32List(count);

    final intents = AnatomicalIntentFactory.build(
      parameters: parameters,
      context: context,
    );
    if (intents.isEmpty) {
      return ConstrainedVertexField.zero();
    }

    final fse = _faceShortEdgePx(context.face, context.imageSize);

    for (final intent in intents) {
      final spec = FaceModelSpecification.forKey(intent.toolKey);
      if (spec == null) {
        continue;
      }
      final magnitude = intent.magnitude.clamp(0.0, 1.0);
      final zoneVertices = _verticesForZones({
        ...spec.primaryZones,
        ...spec.freeZones,
      });

      for (final index in zoneVertices) {
        if (index >= count) {
          continue;
        }
        final role = _roleForVertex(index, spec);
        if (role == VertexRole.rigid) {
          continue;
        }

        final base = FaceWarpUtils.vertexAt(context.mesh, index);
        if (base == null) {
          continue;
        }

        final delta = PilotWarpDisplacement.deltaFor(
          toolKey: intent.toolKey,
          landmarkIndex: index,
          base: base,
          spec: spec,
          face: context.face,
          mesh: context.mesh,
          imageSize: context.imageSize,
          magnitude: magnitude,
          rawIntensity: intent.rawIntensity ?? magnitude,
          linkEyes: context.linkEyes,
          fse: fse,
        );

        var weight = 1.0;
        if (role == VertexRole.semiRigid) {
          weight = semiRigidWeight;
        }

        if (FaceWarpMvpOperations.usesAdditiveComposition(intent.toolKey)) {
          dx[index] += delta.dx * weight;
          dy[index] += delta.dy * weight;
        } else {
          dx[index] = delta.dx * weight;
          dy[index] = delta.dy * weight;
        }
      }
    }

    return ConstrainedVertexField(
      displacements: Float32List.fromList(_interleave(dx, dy, count)),
      landmarkCount: count,
    );
  }

  static ConstrainedVertexField _applySupportWeights({
    required ConstrainedVertexField field,
    required TriMesh mesh,
    required Float32List supportWeights,
  }) {
    final count = FaceWarpFieldMetrics.safeVertexCount(field: field, mesh: mesh);
    final out = Float32List.fromList(field.displacements);

    for (var i = 0; i < count; i++) {
      final core = field.displacementAt(i);
      final w = supportWeights[i].clamp(0.0, 1.0);
      out[i * 2] = core.dx * w;
      out[i * 2 + 1] = core.dy * w;
    }

    return ConstrainedVertexField(
      displacements: out,
      landmarkCount: field.landmarkCount,
    );
  }

  static MvpStageMetrics _metricsFor({
    required String stage,
    required ConstrainedVertexField field,
    required TriMesh mesh,
    required Set<int> roiIndices,
  }) {
    final count = FaceWarpFieldMetrics.safeVertexCount(field: field, mesh: mesh);
    var moved = 0;
    var sum = 0.0;
    var max = 0.0;

    var roiMoved = 0;
    var roiSum = 0.0;
    var roiMax = 0.0;

    for (var i = 0; i < count; i++) {
      final mag = field.displacementAt(i).distance;
      if (mag > _moveThresholdPx) {
        moved++;
        sum += mag;
        if (mag > max) {
          max = mag;
        }
      }
      if (roiIndices.contains(i) && mag > _moveThresholdPx) {
        roiMoved++;
        roiSum += mag;
        if (mag > roiMax) {
          roiMax = mag;
        }
      }
    }

    return MvpStageMetrics(
      stage: stage,
      movedVertexCount: moved,
      maxDisplacementPx: max,
      meanDisplacementPx: moved > 0 ? sum / moved : 0,
      roiMaxDisplacementPx: roiMax,
      roiMeanDisplacementPx: roiMoved > 0 ? roiSum / roiMoved : 0,
      roiMovedVertexCount: roiMoved,
    );
  }

  static double _retention(double from, double to) {
    if (from <= 1e-9) {
      return to <= 1e-9 ? 1.0 : double.infinity;
    }
    return (to / from).clamp(0.0, 10.0);
  }

  static (String, String) _identifyBottleneck(MvpToolIntensityReport at100) {
    final losses = <(String, double, String)>[
      (
        'ACE',
        1.0 - at100.aceRetentionFromGenerator.clamp(0.0, 1.0),
        'clamp/rigid/antiFold reduz ${((1 - at100.aceRetentionFromGenerator) * 100).toStringAsFixed(1)}% vs generator no ROI',
      ),
      (
        'Phase9',
        1.0 - at100.phase9RetentionFromAce.clamp(0.0, 1.0),
        'GlobalJacobianConstraint reduz ${((1 - at100.phase9RetentionFromAce) * 100).toStringAsFixed(1)}% vs ACE no ROI',
      ),
      (
        'GeometricSupport',
        1.0 - at100.effectiveRetentionFromPhase9.clamp(0.0, 1.0),
        'supportWeight reduz ${((1 - at100.effectiveRetentionFromPhase9) * 100).toStringAsFixed(1)}% vs Phase9 no ROI',
      ),
    ];

    losses.sort((a, b) => b.$2.compareTo(a.$2));
    final top = losses.first;
    if (top.$2 < 0.02) {
      return (
        'Generator',
        'Generator já é o limitador — pouca perda downstream (<2% em todos os estágios)',
      );
    }
    return (top.$1, top.$3);
  }

  static String _generatorRecommendation({
    required String toolKey,
    required MvpToolIntensityReport report,
    required (String, String) bottleneck,
    double? faceSlimEffectiveMax,
  }) {
    final ref = faceSlimEffectiveMax ?? 0.0;
    final gap = ref > 0
        ? (1.0 - report.effective.roiMaxDisplacementPx / ref)
        : 0.0;

    final base = switch (toolKey) {
      'face_slim' => 'Referência — sem calibração necessária.',
      'narrow_face' =>
        'Portar edgeWeight^0.72 + zoneWeight(ny) + effectiveMag^1.35 de _faceSlim; remover fator 0.85 fixo.',
      'jaw' =>
        'Substituir ratio linear por edgeWeight^0.72; amplitude via FSE×0.07×effectiveMag (saturar cap no contorno).',
      'v_face' =>
        'Reescrever com FSE×falloff; edgeWeight na mandíbula; expandir para VertexRoleMap.chin (10 pts).',
      'chin' =>
        'Subir narrowFactor mínimo 0.35→0.55; priorizar componente vertical; effectiveMag^1.35.',
      'cheekbone' =>
        'Expandir anel bochecha superior (peso 0.6–1.0); subir coeficientes para saturar ~95% do cap 0.05×FSE.',
      'forehead' =>
        'Expandir além de _foreheadLower (7→~11 pts); falloff vertical; saturar cap 0.05×FSE.',
      _ => 'Revisar generator em pilot_warp_contour_nose.dart.',
    };

    return '$base Gap vs face_slim effective ROI @1.0: ${(gap * 100).toStringAsFixed(0)}%. '
        'Gargalo @1.0: ${bottleneck.$1} — ${bottleneck.$2}';
  }

  static Set<int> _roiIndicesFor(String toolKey) {
    return switch (toolKey) {
      'face_slim' => {
          ...VertexRoleMap.jawLeft,
          ...VertexRoleMap.jawRight,
          ...VertexRoleMap.cheekLeft,
          ...VertexRoleMap.cheekRight,
          ...VertexRoleMap.templeLeft,
          ...VertexRoleMap.templeRight,
        },
      'narrow_face' => {
          ...VertexRoleMap.cheekLeft,
          ...VertexRoleMap.cheekRight,
        },
      'v_face' => {
          ...VertexRoleMap.jawLeft,
          ...VertexRoleMap.jawRight,
          ...VertexRoleMap.chin,
        },
      'jaw' => {
          ...VertexRoleMap.jawLeft,
          ...VertexRoleMap.jawRight,
        },
      'chin' => {...VertexRoleMap.chin},
      'cheekbone' => {
          ...FaceWarpUtils.cheekboneLeft,
          ...FaceWarpUtils.cheekboneRight,
          207,
          206,
          203,
          142,
          126,
          217,
          427,
          436,
          426,
          423,
          266,
          371,
        },
      'forehead' => {
          ..._foreheadLowerIndices,
          127,
          162,
          356,
          389,
        },
      _ => {},
    };
  }

  static String _roiLabel(String toolKey) => switch (toolKey) {
        'face_slim' => 'contorno_lateral (jaw+cheek+temple)',
        'narrow_face' => 'cheekLeft+cheekRight',
        'v_face' => 'jaw+chin',
        'jaw' => 'jawLeft+jawRight',
        'chin' => 'chin',
        'cheekbone' => 'cheekboneLeft+cheekboneRight',
        'forehead' => 'foreheadLower (7 landmarks)',
        _ => toolKey,
      };

  static double _faceShortEdgePx(FaceMeshResult face, Size imageSize) {
    final bounds = FaceWarpUtils.landmarkBounds(
      face,
      imageSize,
      VertexRoleMap.skullContour,
    );
    if (bounds == null || bounds.isEmpty) {
      return math.min(imageSize.width, imageSize.height);
    }
    return math.min(bounds.width, bounds.height);
  }

  static Set<int> _verticesForZones(Set<AnatomicalZone> zones) {
    final out = <int>{};
    for (final zone in zones) {
      out.addAll(VertexRoleMap.landmarksFor(zone));
    }
    return out;
  }

  static VertexRole _roleForVertex(int index, FaceToolSpecification spec) {
    for (final zone in spec.rigidZones) {
      if (VertexRoleMap.landmarksFor(zone).contains(index)) {
        return VertexRole.rigid;
      }
    }
    for (final zone in spec.semiRigidZones) {
      if (VertexRoleMap.landmarksFor(zone).contains(index)) {
        return VertexRole.semiRigid;
      }
    }
    for (final zone in spec.primaryZones) {
      if (VertexRoleMap.landmarksFor(zone).contains(index)) {
        return VertexRole.free;
      }
    }
    for (final zone in spec.freeZones) {
      if (VertexRoleMap.landmarksFor(zone).contains(index)) {
        return VertexRole.free;
      }
    }
    return VertexRole.free;
  }

  static List<double> _interleave(Float32List dx, Float32List dy, int count) {
    final out = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      out[i * 2] = dx[i];
      out[i * 2 + 1] = dy[i];
    }
    return out;
  }

  static void _writeDisplacementHeatmap({
    required TriMesh mesh,
    required ConstrainedVertexField field,
    required int imageWidth,
    required int imageHeight,
    required String outputPath,
    required Set<int> roiIndices,
  }) {
    final heatmap = img.Image(width: imageWidth, height: imageHeight);
    img.fill(heatmap, color: img.ColorRgb8(18, 18, 24));

    final count = FaceWarpFieldMetrics.safeVertexCount(field: field, mesh: mesh);
    var maxMag = 0.0;
    final mags = Float32List(count);
    for (var i = 0; i < count; i++) {
      final mag = field.displacementAt(i).distance;
      mags[i] = mag;
      if (mag > maxMag) {
        maxMag = mag;
      }
    }
    if (maxMag < 1e-9) {
      maxMag = 1.0;
    }

    for (var t = 0; t < mesh.indices.length; t += 3) {
      final i0 = mesh.indices[t];
      final i1 = mesh.indices[t + 1];
      final i2 = mesh.indices[t + 2];
      if (i0 >= count || i1 >= count || i2 >= count) {
        continue;
      }

      final avgMag = (mags[i0] + mags[i1] + mags[i2]) / 3.0;
      if (avgMag <= _moveThresholdPx) {
        continue;
      }

      final p0 = FaceWarpUtils.vertexAt(mesh, i0);
      final p1 = FaceWarpUtils.vertexAt(mesh, i1);
      final p2 = FaceWarpUtils.vertexAt(mesh, i2);
      if (p0 == null || p1 == null || p2 == null) {
        continue;
      }

      final inRoi = roiIndices.contains(i0) ||
          roiIndices.contains(i1) ||
          roiIndices.contains(i2);
      final color = _magnitudeColor(avgMag / maxMag, inRoi: inRoi);

      _fillTriangle(heatmap, p0, p1, p2, color);
    }

    File(outputPath).writeAsBytesSync(img.encodePng(heatmap));
  }

  static img.ColorRgb8 _magnitudeColor(double t, {required bool inRoi}) {
    final x = t.clamp(0.0, 1.0);
    final r = (255 * x).round();
    final g = (180 * (1.0 - x)).round();
    final b = inRoi ? 40 : 80;
    return img.ColorRgb8(r, g, b);
  }

  static void _fillTriangle(
    img.Image image,
    Offset p0,
    Offset p1,
    Offset p2,
    img.ColorRgb8 color,
  ) {
    final minX = math.max(0, math.min(p0.dx, math.min(p1.dx, p2.dx)).floor());
    final maxX = math.min(
      image.width - 1,
      math.max(p0.dx, math.max(p1.dx, p2.dx)).ceil(),
    );
    final minY = math.max(0, math.min(p0.dy, math.min(p1.dy, p2.dy)).floor());
    final maxY = math.min(
      image.height - 1,
      math.max(p0.dy, math.max(p1.dy, p2.dy)).ceil(),
    );

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final pt = Offset(x + 0.5, y + 0.5);
        if (_pointInTriangle(pt, p0, p1, p2)) {
          image.setPixel(x, y, color);
        }
      }
    }
  }

  static bool _pointInTriangle(Offset p, Offset a, Offset b, Offset c) {
    final v0 = c - a;
    final v1 = b - a;
    final v2 = p - a;
    final dot00 = v0.dot(v0);
    final dot01 = v0.dot(v1);
    final dot02 = v0.dot(v2);
    final dot11 = v1.dot(v1);
    final dot12 = v1.dot(v2);
    final invDenom = 1 / (dot00 * dot11 - dot01 * dot01);
    final u = (dot11 * dot02 - dot01 * dot12) * invDenom;
    final v = (dot00 * dot12 - dot01 * dot02) * invDenom;
    return u >= 0 && v >= 0 && (u + v) <= 1;
  }

  static String _markdownReport(
    Map<String, dynamic> summary,
    List<MvpToolCalibrationReport> reports,
  ) {
    final sb = StringBuffer()
      ..writeln('# MVP Calibration — Etapa 1 (Diagnóstico)')
      ..writeln()
      ..writeln('Referência face_slim effective ROI max @1.0: '
          '${summary['faceSlimReferenceEffectiveRoiMaxPx']} px')
      ..writeln();

    for (final r in reports) {
      sb.writeln('## ${r.toolKey}');
      sb.writeln('- **ROI:** ${r.primaryRoi} (${r.primaryRoiVertexCount} landmarks)');
      sb.writeln('- **Heatmap:** `${r.heatmapPath}`');
      sb.writeln('- **Gargalo @1.0:** ${r.primaryBottleneck} — ${r.bottleneckDetail}');
      sb.writeln('- **Recomendação generator:** ${r.generatorRecommendation}');
      sb.writeln();
      sb.writeln('| Intensidade | Gen max ROI | ACE max ROI | P9 max ROI | Eff max ROI | P9 ret | Eff ret | Movidos |');
      sb.writeln('|-------------|-------------|-------------|------------|-------------|--------|---------|---------|');

      for (final ir in r.intensityReports) {
        sb.writeln(
          '| ${ir.intensity} '
          '| ${ir.generator.roiMaxDisplacementPx.toStringAsFixed(2)} '
          '| ${ir.ace.roiMaxDisplacementPx.toStringAsFixed(2)} '
          '| ${ir.phase9.roiMaxDisplacementPx.toStringAsFixed(2)} '
          '| ${ir.effective.roiMaxDisplacementPx.toStringAsFixed(2)} '
          '| ${(ir.phase9RetentionFromAce * 100).toStringAsFixed(1)}% '
          '| ${(ir.effectiveRetentionFromPhase9 * 100).toStringAsFixed(1)}% '
          '| ${ir.effective.roiMovedVertexCount} |',
        );
      }
      sb.writeln();
    }

    return sb.toString();
  }

  /// Mede perda do GeometricSupport por vértice (Phase9 → Effective) @1.0.
  static Map<String, dynamic> measureGeometricSupportLoss({
    required String toolKey,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    double intensity = 1.0,
  }) {
    const engine = FaceMeshDeformationEngine();
    final roiIndices = _roiIndicesFor(toolKey);
    final params = {toolKey: intensity};
    final context = FaceAnatomyContext(
      face: face,
      imageSize: imageSize,
      mesh: mesh,
    );

    final aceField = engine.composeVertexField(
      parameters: params,
      context: context,
      mesh: mesh,
      applyStructuralPipeline: false,
    );
    final phase9Result = FaceWarpStructuralPipeline.apply(
      mesh: mesh,
      inputField: aceField,
    );
    final phase9Field = phase9Result.vertexField;

    final influence = FaceMatteRoi.buildInfluenceMap(
      face: face,
      imageSize: imageSize,
      lateralRadiusExpand: 0.07,
    );
    final supportWeights = GeometricSupport.computeWeights(
      mesh: mesh,
      coreField: phase9Field,
      influenceMap: influence,
      params: const DeformationSupportParams(),
      imageWidth: imageSize.width.round(),
      imageHeight: imageSize.height.round(),
    );
    final effectiveField = _applySupportWeights(
      field: phase9Field,
      mesh: mesh,
      supportWeights: supportWeights,
    );

    final count = FaceWarpFieldMetrics.safeVertexCount(
      field: phase9Field,
      mesh: mesh,
    );
    final perVertex = <Map<String, dynamic>>[];
    var roiMovedBefore = 0;
    var roiMovedAfter = 0;
    double roiMaxBefore = 0, roiMaxAfter = 0;
    double roiSumBefore = 0, roiSumAfter = 0;

    for (var i = 0; i < count; i++) {
      if (!roiIndices.contains(i)) {
        continue;
      }
      final before = phase9Field.displacementAt(i).distance;
      final after = effectiveField.displacementAt(i).distance;
      if (before <= _moveThresholdPx) {
        continue;
      }
      roiMovedBefore++;
      roiSumBefore += before;
      if (before > roiMaxBefore) {
        roiMaxBefore = before;
      }
      if (after > _moveThresholdPx) {
        roiMovedAfter++;
        roiSumAfter += after;
        if (after > roiMaxAfter) {
          roiMaxAfter = after;
        }
      }
      final lossPct = before > 1e-9 ? (1.0 - after / before) * 100 : 0.0;
      perVertex.add({
        'index': i,
        'phase9MagPx': before,
        'effectiveMagPx': after,
        'supportWeight': supportWeights[i],
        'lossPct': lossPct,
      });
    }

    perVertex.sort(
      (a, b) => (b['lossPct'] as double).compareTo(a['lossPct'] as double),
    );

    final avgLossBeforeAfter = roiMaxBefore > 1e-9
        ? (1.0 - roiMaxAfter / roiMaxBefore) * 100
        : 0.0;

    return {
      'toolKey': toolKey,
      'intensity': intensity,
      'roiVertexCount': roiIndices.length,
      'roiMovedBeforeSupport': roiMovedBefore,
      'roiMovedAfterSupport': roiMovedAfter,
      'roiMaxBeforeSupportPx': roiMaxBefore,
      'roiMaxAfterSupportPx': roiMaxAfter,
      'roiMeanBeforeSupportPx':
          roiMovedBefore > 0 ? roiSumBefore / roiMovedBefore : 0,
      'roiMeanAfterSupportPx':
          roiMovedAfter > 0 ? roiSumAfter / roiMovedAfter : 0,
      'roiMaxLossPct': avgLossBeforeAfter,
      'primaryBottleneckIsSupport': avgLossBeforeAfter >= 15.0 &&
          roiMovedAfter < roiMovedBefore * 0.85,
      'perVertex': perVertex,
    };
  }
}

extension on Offset {
  double dot(Offset other) => dx * other.dx + dy * other.dy;
}

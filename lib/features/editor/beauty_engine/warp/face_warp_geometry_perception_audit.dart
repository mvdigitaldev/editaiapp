import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset, Size;
import 'package:image/image.dart' as img;

import '../body_reshape/maps/influence_map.dart';
import '../models/face_mesh_result.dart';
import '../models/mesh_region.dart';
import '../models/tri_mesh.dart';
import '../quality/image_quality_metrics.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/anatomical_intent_factory.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'anatomy/face_matte_roi.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'anatomy/face_model_specification.dart';
import 'anatomy/pilot_warp_displacement.dart';
import 'anatomy/vertex_role_map.dart';
import '../filters/face/face_warp_utils.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_fse_compression_audit.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;
import 'face_warp_structural_pipeline.dart';

/// Investigação geométrica: ROI, pesos e sensibilidade visual.
abstract final class FaceWarpGeometryPerceptionAudit {
  FaceWarpGeometryPerceptionAudit._();

  static const tools = ['chin', 'cheekbone', 'narrow_face'];
  static const sensitivitySteps = [0.10, 0.20, 0.30];
  static const currentFse = {
    'chin': 0.075,
    'cheekbone': 0.07,
    'narrow_face': 0.08,
  };

  static Future<Map<String, dynamic>> run({
    required List<FseAuditFaceInput> analysisFaces,
    required List<FseAuditFaceInput> renderFaces,
    String outputDirectory =
        '/Users/leonardo/Documents/Projetos/editaiapp/.cursor/geometry-perception-audit',
  }) async {
    Directory(outputDirectory).createSync(recursive: true);
    final toolReports = <Map<String, dynamic>>[];

    for (final toolKey in tools) {
      toolReports.add(await _auditTool(
        toolKey: toolKey,
        analysisFaces: analysisFaces,
        renderFaces: renderFaces,
        outputDirectory: outputDirectory,
      ));
    }

    final report = {
      'phase': 'geometry-perception-audit',
      'analysisFaceCount': analysisFaces.length,
      'renderFaceCount': renderFaces.length,
      'tools': toolReports,
      'ranking': _globalRanking(toolReports),
    };

    File('$outputDirectory/geometry-perception-audit.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    File('$outputDirectory/geometry-perception-audit.md')
        .writeAsStringSync(_markdown(report));

    return report;
  }

  static Future<Map<String, dynamic>> _auditTool({
    required String toolKey,
    required List<FseAuditFaceInput> analysisFaces,
    required List<FseAuditFaceInput> renderFaces,
    required String outputDirectory,
  }) async {
    const engine = FaceMeshDeformationEngine();
    final toolDir = '$outputDirectory/$toolKey';
    Directory(toolDir).createSync(recursive: true);

    final roiAnalysis = <Map<String, dynamic>>[];
    final weightBreakdowns = <Map<String, dynamic>>[];

    for (final face in analysisFaces) {
      final bd = _computeWeightBreakdown(
        toolKey: toolKey,
        engine: engine,
        input: face,
      );
      weightBreakdowns.add(bd);
      roiAnalysis.add({
        'faceId': face.id,
        'roiStats': bd['roiStats'],
        'weightStats': bd['weightStats'],
      });
    }

    // Heatmap on first synthetic face
    final heatmapFace = analysisFaces.firstWhere(
      (f) => f.isSynthetic,
      orElse: () => analysisFaces.first,
    );
    final heatmapBd = _computeWeightBreakdown(
      toolKey: toolKey,
      engine: engine,
      input: heatmapFace,
    );
    final heatmapPath = '$toolDir/contribution-heatmap-${heatmapFace.id}.png';
    _writeContributionHeatmap(
      mesh: heatmapFace.mesh,
      vertices: (heatmapBd['vertices'] as List).cast<Map<String, dynamic>>(),
      imageWidth: heatmapFace.imageSize.width.round(),
      imageHeight: heatmapFace.imageSize.height.round(),
      outputPath: heatmapPath,
    );

    final sensitivity = await _runSensitivitySweep(
      toolKey: toolKey,
      engine: engine,
      faces: renderFaces,
      outputDirectory: toolDir,
    );

    final simulations = await _runStructuralSimulations(
      toolKey: toolKey,
      engine: engine,
      faces: renderFaces,
      outputDirectory: toolDir,
    );

    final aggregateRoi = _aggregateRoiStats(weightBreakdowns);
    final ranking = _rankBottlenecks(
      toolKey: toolKey,
      aggregateRoi: aggregateRoi,
      sensitivity: sensitivity,
      simulations: simulations,
    );

    return {
      'toolKey': toolKey,
      'currentFse': currentFse[toolKey],
      'heatmapPath': heatmapPath,
      'aggregateRoi': aggregateRoi,
      'sensitivityTable': sensitivity['table'],
      'structuralSimulations': simulations,
      'bottleneckRanking': ranking,
      'perFaceRoi': roiAnalysis,
    };
  }

  // ---------------------------------------------------------------------------
  // Weight breakdown + ROI stats
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _computeWeightBreakdown({
    required String toolKey,
    required FaceMeshDeformationEngine engine,
    required FseAuditFaceInput input,
  }) {
    const intensity = 1.0;
    final params = {toolKey: intensity};
    final context = FaceAnatomyContext(
      face: input.face,
      imageSize: input.imageSize,
      mesh: input.mesh,
    );
    final spec = FaceModelSpecification.forKey(toolKey)!;
    final fse = _faceShortEdgePx(input.face, input.imageSize);
    final centerX = FaceWarpUtils.faceCenterX(input.face, input.imageSize);

    final intents = AnatomicalIntentFactory.build(
      parameters: params,
      context: context,
    );
    final magnitude = intents.isEmpty ? 0.0 : intents.first.magnitude;
    final rawIntensity = intents.isEmpty ? 0.0 : intents.first.rawIntensity ?? magnitude;

    final aceField = engine.composeVertexField(
      parameters: params,
      context: context,
      mesh: input.mesh,
      applyStructuralPipeline: false,
    );
    final phase9Field = FaceWarpStructuralPipeline.apply(
      mesh: input.mesh,
      inputField: aceField,
    ).vertexField;

    final influence = FaceMatteRoi.buildInfluenceMap(
      face: input.face,
      imageSize: input.imageSize,
      lateralRadiusExpand: 0.07,
    );
    final supportWeights = GeometricSupport.computeWeights(
      mesh: input.mesh,
      coreField: phase9Field,
      influenceMap: influence,
      params: const DeformationSupportParams(),
      imageWidth: input.imageSize.width.round(),
      imageHeight: input.imageSize.height.round(),
    );

    final analysisIndices = _analysisIndicesFor(toolKey);
    final vertices = <Map<String, dynamic>>[];
    var sumEffective = 0.0;
    var countSig = 0;
    var countAbove1 = 0;
    var countAbove05 = 0;
    var countAbove025 = 0;

    for (final index in analysisIndices) {
      final base = FaceWarpUtils.vertexAt(input.mesh, index);
      if (base == null) {
        continue;
      }

      final genDelta = PilotWarpDisplacement.deltaFor(
        toolKey: toolKey,
        landmarkIndex: index,
        base: base,
        spec: spec,
        face: input.face,
        mesh: input.mesh,
        imageSize: input.imageSize,
        magnitude: magnitude,
        rawIntensity: rawIntensity,
        linkEyes: true,
        fse: fse,
      );

      final edgeW = _edgeWeightFor(toolKey, base, centerX, fse);
      final zoneW = _zoneWeightFor(toolKey, base.dy / input.imageSize.height);
      final tierW = _tierWeightFor(toolKey, index);
      final genMag = genDelta.distance;
      final aceMag = aceField.displacementAt(index).distance;
      final p9Mag = phase9Field.displacementAt(index).distance;
      final supportW = index < supportWeights.length ? supportWeights[index] : 1.0;
      final effectiveMag = p9Mag * supportW;

      final pilotProduct = genMag > 1e-6 ? effectiveMag / genMag : 0.0;

      if (effectiveMag > 0.25) {
        countAbove025++;
      }
      if (effectiveMag > 0.5) {
        countAbove05++;
      }
      if (effectiveMag > 1.0) {
        countAbove1++;
        countSig++;
      }

      sumEffective += effectiveMag;

      vertices.add({
        'index': index,
        'x': base.dx,
        'y': base.dy,
        'genMagPx': genMag,
        'edgeWeight': edgeW,
        'zoneWeight': zoneW,
        'tierWeight': tierW,
        'aceMagPx': aceMag,
        'phase9MagPx': p9Mag,
        'supportWeight': supportW,
        'effectiveMagPx': effectiveMag,
        'pilotWeightProduct': edgeW * zoneW * tierW,
        'totalAttenuation': pilotProduct,
      });
    }

    for (final v in vertices) {
      v['contributionPct'] =
          sumEffective > 0 ? (v['effectiveMagPx'] as double) / sumEffective * 100 : 0.0;
    }

    vertices.sort(
      (a, b) => (b['effectiveMagPx'] as double).compareTo(a['effectiveMagPx'] as double),
    );

    final active = vertices.where((v) => (v['effectiveMagPx'] as double) > 0.25).toList();

    return {
      'faceId': input.id,
      'vertices': vertices,
      'roiStats': {
        'analysisVertexCount': analysisIndices.length,
        'activeAbove0.25px': countAbove025,
        'activeAbove0.5px': countAbove05,
        'significantAbove1px': countAbove1,
        'top3ContributionPct': active.take(3).map((v) => v['contributionPct']).toList(),
        'meanEffectiveMagPx': active.isEmpty
            ? 0.0
            : active.map((v) => v['effectiveMagPx'] as double).reduce((a, b) => a + b) /
                active.length,
        'maxEffectiveMagPx':
            active.isEmpty ? 0.0 : active.first['effectiveMagPx'] as double,
      },
      'weightStats': {
        'avgEdgeWeight': _avg(active, 'edgeWeight'),
        'avgZoneWeight': _avg(active, 'zoneWeight'),
        'avgTierWeight': _avg(active, 'tierWeight'),
        'avgSupportWeight': _avg(active, 'supportWeight'),
        'avgPilotProduct': _avg(active, 'pilotWeightProduct'),
        'verticesWithEdgeBelow0.5': active
            .where((v) => (v['edgeWeight'] as double) < 0.5 && toolKey == 'narrow_face')
            .length,
        'verticesWithSupportBelow0.85':
            active.where((v) => (v['supportWeight'] as double) < 0.85).length,
        'verticesWithTierBelow1':
            active.where((v) => (v['tierWeight'] as double) < 0.99).length,
      },
    };
  }

  static double _avg(List<Map<String, dynamic>> verts, String key) {
    if (verts.isEmpty) {
      return 0.0;
    }
    return verts.map((v) => v[key] as double).reduce((a, b) => a + b) / verts.length;
  }

  static Map<String, dynamic> _aggregateRoiStats(List<Map<String, dynamic>> bds) {
    double mean(String path, String key) {
      var sum = 0.0;
      for (final bd in bds) {
        sum += (bd[path] as Map)[key] as num;
      }
      return sum / bds.length;
    }

    return {
      'avgAnalysisVertices': mean('roiStats', 'analysisVertexCount'),
      'avgSignificantAbove1px': mean('roiStats', 'significantAbove1px'),
      'avgActiveAbove0.25px': mean('roiStats', 'activeAbove0.25px'),
      'avgMeanEffectiveMagPx': mean('roiStats', 'meanEffectiveMagPx'),
      'avgMaxEffectiveMagPx': mean('roiStats', 'maxEffectiveMagPx'),
      'avgEdgeWeight': mean('weightStats', 'avgEdgeWeight'),
      'avgZoneWeight': mean('weightStats', 'avgZoneWeight'),
      'avgTierWeight': mean('weightStats', 'avgTierWeight'),
      'avgSupportWeight': mean('weightStats', 'avgSupportWeight'),
      'avgVerticesEdgeBelow0.5': mean('weightStats', 'verticesWithEdgeBelow0.5'),
      'avgVerticesSupportBelow0.85': mean('weightStats', 'verticesWithSupportBelow0.85'),
      'avgVerticesTierBelow1': mean('weightStats', 'verticesWithTierBelow1'),
    };
  }

  // ---------------------------------------------------------------------------
  // Sensitivity sweep (render-based)
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _runSensitivitySweep({
    required String toolKey,
    required FaceMeshDeformationEngine engine,
    required List<FseAuditFaceInput> faces,
    required String outputDirectory,
  }) async {
    final table = <String, Map<String, List<double>>>{};
    for (final param in [
      'ROI',
      'edgeWeight',
      'zoneWeight',
      'supportWeight',
      'maxDisplacementFse',
    ]) {
      table[param] = {for (final s in sensitivitySteps) '+${(s * 100).round()}%': []};
    }

    for (final face in faces) {
      final baselineField = _buildFieldForVariant(
        toolKey: toolKey,
        engine: engine,
        input: face,
        mode: _VariantMode.baseline,
      );
      final baselineFieldVis = _fieldVisualProxy(face, baselineField, toolKey);

      // Render baseline once for validation @+30%
      final baselineRender = await _renderField(
        input: face,
        phase9Field: baselineField,
        toolKey: toolKey,
      );

      final baselineRenderVis = _measureVisual(
        source: face.sourceRgba,
        rendered: baselineRender,
        baselineRendered: null,
        face: face.face,
        imageSize: face.imageSize,
      );

      for (final step in sensitivitySteps) {
        for (final param in table.keys) {
          final variantField = _buildFieldForVariant(
            toolKey: toolKey,
            engine: engine,
            input: face,
            mode: _VariantMode.sensitivity,
            param: param,
            step: step,
          );
          final fieldGain = _fieldVisualProxyGain(
            baselineFieldVis,
            variantField,
            face,
            toolKey,
          );

          // Render só @+30% para calibrar proxy
          if ((step - 0.30).abs() < 0.01) {
            final variantRender = await _renderField(
              input: face,
              phase9Field: variantField,
              toolKey: toolKey,
            );
            final pairVis = _measureVisual(
              source: face.sourceRgba,
              rendered: variantRender,
              baselineRendered: baselineRender,
              face: face.face,
              imageSize: face.imageSize,
            );
            final renderGain = _visualGainPct(baselineRenderVis, pairVis);
            // Blend: usa render real quando disponível
            table[param]!['+30%']!.add(renderGain > 0 ? renderGain : fieldGain);
          } else {
            table[param]!['+${(step * 100).round()}%']!.add(fieldGain);
          }
        }
      }
    }

    final aggregated = <String, Map<String, double>>{};
    for (final entry in table.entries) {
      aggregated[entry.key] = {};
      for (final stepEntry in entry.value.entries) {
        final vals = stepEntry.value;
        aggregated[entry.key]![stepEntry.key] =
            vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
      }
    }

    return {'table': aggregated, 'raw': table};
  }

  static Future<List<Map<String, dynamic>>> _runStructuralSimulations({
    required String toolKey,
    required FaceMeshDeformationEngine engine,
    required List<FseAuditFaceInput> faces,
    required String outputDirectory,
  }) async {
    final modes = [
      ('expandRoi', _VariantMode.expandRoi),
      ('boostWeights', _VariantMode.boostWeights),
      ('addNeighbors', _VariantMode.addNeighbors),
    ];

    final results = <Map<String, dynamic>>[];
    for (final (label, mode) in modes) {
      final gains = <double>[];
      for (final face in faces) {
        final baseline = await _renderVariant(
          toolKey: toolKey,
          engine: engine,
          input: face,
          mode: _VariantMode.baseline,
        );
        final variant = await _renderVariant(
          toolKey: toolKey,
          engine: engine,
          input: face,
          mode: mode,
        );
        final pairVis = _measureVisual(
          source: face.sourceRgba,
          rendered: variant.rgba,
          baselineRendered: baseline.rgba,
          face: face.face,
          imageSize: face.imageSize,
        );
        gains.add(_visualGainPct(baseline.visual, pairVis));
      }
      results.add({
        'simulation': label,
        'avgVisualGainPct': gains.reduce((a, b) => a + b) / gains.length,
        'perFaceGainPct': gains,
      });
    }
    results.sort(
      (a, b) => (b['avgVisualGainPct'] as double).compareTo(a['avgVisualGainPct'] as double),
    );
    return results;
  }

  static double _visualGainPct(
    Map<String, dynamic> baseline,
    Map<String, dynamic> variant,
  ) {
    final baseDe = baseline['roiMeanDeltaE'] as double;
    final pairDe = variant['roiPairMeanDeltaE'] as double;
    if (baseDe <= 1e-6) {
      return 0.0;
    }
    return pairDe / baseDe * 100;
  }

  // ---------------------------------------------------------------------------
  // Render variants
  // ---------------------------------------------------------------------------

  static Future<Uint8List> _renderField({
    required FseAuditFaceInput input,
    required ConstrainedVertexField phase9Field,
    required String toolKey,
  }) async {
    final w = input.imageSize.width.round();
    final h = input.imageSize.height.round();
    final influence = FaceMatteRoi.buildInfluenceMap(
      face: input.face,
      imageSize: input.imageSize,
      lateralRadiusExpand: 0.07,
    );
    final payload = FaceMeshForwardPayload(
      mesh: input.mesh,
      vertexField: phase9Field,
      influenceMap: influence,
    );
    return FaceMeshForwardWarp.apply(
      rgba: Uint8List.fromList(input.sourceRgba),
      width: w,
      height: h,
      payload: payload,
      runId: 'geom-field-$toolKey',
    );
  }

  static double _fieldVisualProxy(
    FseAuditFaceInput input,
    ConstrainedVertexField field,
    String toolKey,
  ) {
    final indices = _analysisIndicesFor(toolKey);
    var sum = 0.0;
    var n = 0;
    for (final i in indices) {
      final mag = field.displacementAt(i).distance;
      if (mag > 0.05) {
        sum += mag;
        n++;
      }
    }
    return n > 0 ? sum / n : 0.0;
  }

  static double _fieldVisualProxyGain(
    double baselineProxy,
    ConstrainedVertexField variantField,
    FseAuditFaceInput input,
    String toolKey,
  ) {
    final variantProxy = _fieldVisualProxy(input, variantField, toolKey);
    if (baselineProxy <= 1e-6) {
      return 0.0;
    }
    return (variantProxy / baselineProxy - 1) * 100;
  }

  static ConstrainedVertexField _buildFieldForVariant({
    required String toolKey,
    required FaceMeshDeformationEngine engine,
    required FseAuditFaceInput input,
    required _VariantMode mode,
    String? param,
    double step = 0,
  }) {
    final params = {toolKey: 1.0};
    final context = FaceAnatomyContext(
      face: input.face,
      imageSize: input.imageSize,
      mesh: input.mesh,
    );
    final influence = FaceMatteRoi.buildInfluenceMap(
      face: input.face,
      imageSize: input.imageSize,
      lateralRadiusExpand: 0.07,
    );

    FaceModelSpecification.maxDisplacementFseOverrides = null;
    if (mode == _VariantMode.sensitivity && param == 'maxDisplacementFse') {
      FaceModelSpecification.maxDisplacementFseOverrides = {
        toolKey: (currentFse[toolKey] ?? 0.08) * (1 + step),
      };
    }

    try {
      if (mode == _VariantMode.expandRoi ||
          mode == _VariantMode.addNeighbors ||
          (mode == _VariantMode.sensitivity && param == 'ROI')) {
        return _buildExpandedField(
          toolKey: toolKey,
          engine: engine,
          input: input,
          expandFactor: mode == _VariantMode.sensitivity ? step : 0.25,
          addNeighbors: mode == _VariantMode.addNeighbors ||
              (mode == _VariantMode.sensitivity && param == 'ROI'),
        );
      }
      if (mode == _VariantMode.boostWeights ||
          (mode == _VariantMode.sensitivity &&
              (param == 'edgeWeight' ||
                  param == 'zoneWeight' ||
                  param == 'supportWeight'))) {
        final baseField = engine.composeVertexField(
          parameters: params,
          context: context,
          mesh: input.mesh,
        );
        return _applyWeightBoost(
          toolKey: toolKey,
          input: input,
          phase9Field: baseField,
          influence: influence,
          param: mode == _VariantMode.boostWeights ? 'allWeights' : param!,
          step: mode == _VariantMode.boostWeights ? 0.25 : step,
        );
      }
      return engine.composeVertexField(
        parameters: params,
        context: context,
        mesh: input.mesh,
      );
    } finally {
      FaceModelSpecification.maxDisplacementFseOverrides = null;
    }
  }

  static Future<({Map<String, dynamic> visual, Uint8List rgba})> _renderVariant({
    required String toolKey,
    required FaceMeshDeformationEngine engine,
    required FseAuditFaceInput input,
    required _VariantMode mode,
    String? param,
    double step = 0,
  }) async {
    final phase9Field = _buildFieldForVariant(
      toolKey: toolKey,
      engine: engine,
      input: input,
      mode: mode,
      param: param,
      step: step,
    );
    final rendered = await _renderField(
      input: input,
      phase9Field: phase9Field,
      toolKey: toolKey,
    );
    final visual = _measureVisual(
      source: input.sourceRgba,
      rendered: rendered,
      baselineRendered: null,
      face: input.face,
      imageSize: input.imageSize,
    );
    return (visual: visual, rgba: rendered);
  }

  static ConstrainedVertexField _applyWeightBoost({
    required String toolKey,
    required FseAuditFaceInput input,
    required ConstrainedVertexField phase9Field,
    required InfluenceMap influence,
    required String param,
    required double step,
  }) {
    final count = FaceWarpFieldMetrics.safeVertexCount(
      field: phase9Field,
      mesh: input.mesh,
    );
    final fse = _faceShortEdgePx(input.face, input.imageSize);
    final centerX = FaceWarpUtils.faceCenterX(input.face, input.imageSize);
    final supportWeights = GeometricSupport.computeWeights(
      mesh: input.mesh,
      coreField: phase9Field,
      influenceMap: influence,
      params: const DeformationSupportParams(),
      imageWidth: input.imageSize.width.round(),
      imageHeight: input.imageSize.height.round(),
    );

    final out = Float32List.fromList(phase9Field.displacements);
    final boost = 1.0 + step;

    for (var i = 0; i < count; i++) {
      final core = phase9Field.displacementAt(i);
      if (core.distance <= 0.05) {
        continue;
      }
      final base = FaceWarpUtils.vertexAt(input.mesh, i);
      if (base == null) {
        continue;
      }

      var factor = 1.0;
      if (param == 'allWeights' || param == 'edgeWeight') {
        final ew = _edgeWeightFor(toolKey, base, centerX, fse);
        if (ew < 0.99 && toolKey == 'narrow_face') {
          factor *= 1.0 + step * (1.0 - ew);
        }
      }
      if (param == 'allWeights' || param == 'zoneWeight') {
        final zw = _zoneWeightFor(toolKey, base.dy / input.imageSize.height);
        if (zw < 0.99 && toolKey == 'narrow_face') {
          factor *= 1.0 + step * (1.0 - zw);
        }
      }
      if (param == 'allWeights' || param == 'supportWeight') {
        final sw = i < supportWeights.length ? supportWeights[i] : 1.0;
        if (sw < 0.99) {
          factor *= 1.0 + step * (1.0 - sw);
        }
      }
      if (param == 'allWeights' && toolKey == 'cheekbone') {
        final tw = _tierWeightFor(toolKey, i);
        if (tw < 0.99) {
          factor *= 1.0 + step * (1.0 - tw);
        }
      }

      out[i * 2] = core.dx * factor;
      out[i * 2 + 1] = core.dy * factor;
    }

    return ConstrainedVertexField(displacements: out, landmarkCount: phase9Field.landmarkCount);
  }

  static ConstrainedVertexField _buildExpandedField({
    required String toolKey,
    required FaceMeshDeformationEngine engine,
    required FseAuditFaceInput input,
    required double expandFactor,
    required bool addNeighbors,
  }) {
    final baseField = engine.composeVertexField(
      parameters: {toolKey: 1.0},
      context: FaceAnatomyContext(
        face: input.face,
        imageSize: input.imageSize,
        mesh: input.mesh,
      ),
      mesh: input.mesh,
    );

    final expandedIndices = _expandedIndicesFor(toolKey, expandFactor);
    final spec = FaceModelSpecification.forKey(toolKey)!;
    final fse = _faceShortEdgePx(input.face, input.imageSize);
    final context = FaceAnatomyContext(
      face: input.face,
      imageSize: input.imageSize,
      mesh: input.mesh,
    );
    final intents = AnatomicalIntentFactory.build(
      parameters: {toolKey: 1.0},
      context: context,
    );
    final magnitude = intents.first.magnitude;
    final raw = intents.first.rawIntensity ?? magnitude;

    final out = Float32List.fromList(baseField.displacements);
    final count = FaceWarpFieldMetrics.safeVertexCount(field: baseField, mesh: input.mesh);

    for (final index in expandedIndices) {
      if (index >= count) {
        continue;
      }
      if (baseField.displacementAt(index).distance > 0.05) {
        continue;
      }

      Offset delta;
      if (addNeighbors) {
        delta = _interpolateFromNeighbors(
          index: index,
          field: baseField,
          mesh: input.mesh,
          analysisIndices: _analysisIndicesFor(toolKey),
        );
      } else {
        delta = PilotWarpDisplacement.deltaFor(
          toolKey: toolKey,
          landmarkIndex: index,
          base: FaceWarpUtils.vertexAt(input.mesh, index)!,
          spec: spec,
          face: input.face,
          mesh: input.mesh,
          imageSize: input.imageSize,
          magnitude: magnitude,
          rawIntensity: raw,
          linkEyes: true,
          fse: fse,
        );
      }

      if (delta.distance <= 0.05) {
        continue;
      }
      out[index * 2] = delta.dx;
      out[index * 2 + 1] = delta.dy;
    }

    final injected = ConstrainedVertexField(
      displacements: out,
      landmarkCount: baseField.landmarkCount,
    );
    return FaceWarpStructuralPipeline.apply(
      mesh: input.mesh,
      inputField: injected,
    ).vertexField;
  }

  static Offset _interpolateFromNeighbors({
    required int index,
    required ConstrainedVertexField field,
    required TriMesh mesh,
    required Set<int> analysisIndices,
  }) {
    final pos = FaceWarpUtils.vertexAt(mesh, index);
    if (pos == null) {
      return Offset.zero;
    }
    var bestDist = double.infinity;
    Offset bestDelta = Offset.zero;
    for (final i in analysisIndices) {
      final p = FaceWarpUtils.vertexAt(mesh, i);
      if (p == null) {
        continue;
      }
      final d = (p - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        bestDelta = field.displacementAt(i);
      }
    }
    return Offset(bestDelta.dx * 0.75, bestDelta.dy * 0.75);
  }

  static Map<String, dynamic> _measureVisual({
    required Uint8List source,
    required Uint8List rendered,
    required Uint8List? baselineRendered,
    required FaceMeshResult face,
    required Size imageSize,
  }) {
    final w = imageSize.width.round();
    final h = imageSize.height.round();
    final roi = _faceOvalBBox(face, imageSize);

    var sumDe = 0.0;
    var nShift = 0;
    var roiPixels = 0;
    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        roiPixels++;
        final o = (y * w + x) * 4;
        final dr = rendered[o] - source[o];
        final dg = rendered[o + 1] - source[o + 1];
        final db = rendered[o + 2] - source[o + 2];
        if (dr == 0 && dg == 0 && db == 0) {
          continue;
        }
        nShift++;
        sumDe += math.sqrt(
          dr * dr.toDouble() + dg * dg.toDouble() + db * db.toDouble(),
        );
      }
    }

    var pairSum = 0.0;
    var pairN = 0;
    if (baselineRendered != null) {
      for (var y = roi.y0; y <= roi.y1; y++) {
        for (var x = roi.x0; x <= roi.x1; x++) {
          final o = (y * w + x) * 4;
          final dr = rendered[o] - baselineRendered[o];
          final dg = rendered[o + 1] - baselineRendered[o + 1];
          final db = rendered[o + 2] - baselineRendered[o + 2];
          if (dr == 0 && dg == 0 && db == 0) {
            continue;
          }
          pairN++;
          pairSum += math.sqrt(
            dr * dr.toDouble() + dg * dg.toDouble() + db * db.toDouble(),
          );
        }
      }
    }

    return {
      'ssimVsSource': ImageQualityMetrics.ssim(source, rendered, width: w, height: h),
      'roiMeanDeltaE': nShift > 0 ? sumDe / nShift : 0.0,
      'roiShiftedPixelPct': roiPixels > 0 ? nShift / roiPixels : 0.0,
      'roiPairMeanDeltaE': pairN > 0 ? pairSum / pairN : 0.0,
    };
  }

  // ---------------------------------------------------------------------------
  // Heatmap
  // ---------------------------------------------------------------------------

  static void _writeContributionHeatmap({
    required TriMesh mesh,
    required List<Map<String, dynamic>> vertices,
    required int imageWidth,
    required int imageHeight,
    required String outputPath,
  }) {
    final heatmap = img.Image(width: imageWidth, height: imageHeight);
    img.fill(heatmap, color: img.ColorRgb8(14, 14, 20));

    final contribByIndex = <int, double>{};
    var maxC = 0.0;
    for (final v in vertices) {
      final c = v['contributionPct'] as double;
      contribByIndex[v['index'] as int] = c;
      if (c > maxC) {
        maxC = c;
      }
    }
    if (maxC < 1e-9) {
      maxC = 1.0;
    }

    final count = mesh.vertices.length ~/ 2;
    for (var t = 0; t < mesh.indices.length; t += 3) {
      final i0 = mesh.indices[t];
      final i1 = mesh.indices[t + 1];
      final i2 = mesh.indices[t + 2];
      if (i0 >= count || i1 >= count || i2 >= count) {
        continue;
      }
      final avg = ((contribByIndex[i0] ?? 0) +
              (contribByIndex[i1] ?? 0) +
              (contribByIndex[i2] ?? 0)) /
          3.0;
      if (avg <= 0.01) {
        continue;
      }

      final p0 = Offset(mesh.vertices[i0 * 2], mesh.vertices[i0 * 2 + 1]);
      final p1 = Offset(mesh.vertices[i1 * 2], mesh.vertices[i1 * 2 + 1]);
      final p2 = Offset(mesh.vertices[i2 * 2], mesh.vertices[i2 * 2 + 1]);
      final tNorm = (avg / maxC).clamp(0.0, 1.0);
      final color = _contributionColor(tNorm);
      _fillTriangle(heatmap, p0, p1, p2, color);
    }

    // Vertex dots
    for (final v in vertices) {
      if ((v['effectiveMagPx'] as double) <= 0.25) {
        continue;
      }
      final x = (v['x'] as double).round().clamp(0, imageWidth - 1);
      final y = (v['y'] as double).round().clamp(0, imageHeight - 1);
      final tNorm = ((v['contributionPct'] as double) / maxC).clamp(0.0, 1.0);
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final px = (x + dx).clamp(0, imageWidth - 1);
          final py = (y + dy).clamp(0, imageHeight - 1);
          heatmap.setPixel(
            px,
            py,
            _contributionColor(tNorm),
          );
        }
      }
    }

    File(outputPath).writeAsBytesSync(img.encodePng(heatmap));
  }

  static img.ColorRgb8 _contributionColor(double t) {
    final r = (255 * t).round().clamp(0, 255);
    final g = (180 * (1 - t) + 40 * t).round().clamp(0, 255);
    final b = (255 * (1 - t)).round().clamp(0, 255);
    return img.ColorRgb8(r, g, b);
  }

  static void _fillTriangle(
    img.Image image,
    Offset p0,
    Offset p1,
    Offset p2,
    img.ColorRgb8 color,
  ) {
    final minY = [p0.dy, p1.dy, p2.dy].reduce(math.min).floor().clamp(0, image.height - 1);
    final maxY = [p0.dy, p1.dy, p2.dy].reduce(math.max).ceil().clamp(0, image.height - 1);
    final minX = [p0.dx, p1.dx, p2.dx].reduce(math.min).floor().clamp(0, image.width - 1);
    final maxX = [p0.dx, p1.dx, p2.dx].reduce(math.max).ceil().clamp(0, image.width - 1);

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        if (_pointInTriangle(Offset(x + 0.5, y + 0.5), p0, p1, p2)) {
          image.setPixel(x, y, color);
        }
      }
    }
  }

  static bool _pointInTriangle(Offset p, Offset a, Offset b, Offset c) {
    final v0 = c - a;
    final v1 = b - a;
    final v2 = p - a;
    final dot00 = v0.dx * v0.dx + v0.dy * v0.dy;
    final dot01 = v0.dx * v1.dx + v0.dy * v1.dy;
    final dot02 = v0.dx * v2.dx + v0.dy * v2.dy;
    final dot11 = v1.dx * v1.dx + v1.dy * v1.dy;
    final dot12 = v1.dx * v2.dx + v1.dy * v2.dy;
    final inv = 1 / (dot00 * dot11 - dot01 * dot01);
    final u = (dot11 * dot02 - dot01 * dot12) * inv;
    final v = (dot00 * dot12 - dot01 * dot02) * inv;
    return u >= 0 && v >= 0 && u + v <= 1;
  }

  // ---------------------------------------------------------------------------
  // Ranking
  // ---------------------------------------------------------------------------

  static List<Map<String, dynamic>> _rankBottlenecks({
    required String toolKey,
    required Map<String, dynamic> aggregateRoi,
    required Map<String, dynamic> sensitivity,
    required List<Map<String, dynamic>> simulations,
  }) {
    final table = sensitivity['table'] as Map<String, Map<String, double>>;
    final candidates = <(String, double, String)>[];

    void add(String name, double gain30, String reason) {
      candidates.add((name, gain30, reason));
    }

    add('maxDisplacementFse', table['maxDisplacementFse']?['+30%'] ?? 0, 'Cap global amplitude');
    add('ROI', table['ROI']?['+30%'] ?? 0, 'Área espacial afetada');
    add('edgeWeight', table['edgeWeight']?['+30%'] ?? 0, 'Atenuação lateral narrow_face');
    add('zoneWeight', table['zoneWeight']?['+30%'] ?? 0, 'Atenuação vertical narrow_face');
    add('supportWeight', table['supportWeight']?['+30%'] ?? 0, 'GeometricSupport contorno');
    if (toolKey == 'cheekbone') {
      add('tierWeight', (table['edgeWeight']?['+30%'] ?? 0) * 0.8, 'Anel 0.65× vs core');
    }

    candidates.sort((a, b) => b.$2.compareTo(a.$2));

    final ranked = <Map<String, dynamic>>[];
    for (var i = 0; i < candidates.length && i < 4; i++) {
      final c = candidates[i];
      ranked.add({
        'rank': i + 1,
        'parameter': c.$1,
        'estimatedVisualGainAt30pct': c.$2.round(),
        'estimatedVisualGainAt10pct': (table[c.$1]?['+10%'] ?? c.$2 / 3).round(),
        'reason': c.$3,
      });
    }

    return ranked;
  }

  static List<Map<String, dynamic>> _globalRanking(List<Map<String, dynamic>> tools) {
    return tools
        .map((t) => {
              'tool': t['toolKey'],
              'ranking': t['bottleneckRanking'],
              'bestSimulation': (t['structuralSimulations'] as List).first,
            })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Set<int> _analysisIndicesFor(String toolKey) => switch (toolKey) {
        'narrow_face' => {
            ...VertexRoleMap.cheekLeft,
            ...VertexRoleMap.cheekRight,
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
        _ => {},
      };

  static Set<int> _expandedIndicesFor(String toolKey, double factor) {
    final base = _analysisIndicesFor(toolKey);
    final out = {...base};
    switch (toolKey) {
      case 'narrow_face':
        out.addAll(VertexRoleMap.jawLeft);
        out.addAll(VertexRoleMap.jawRight);
        if (factor >= 0.2) {
          out.addAll(VertexRoleMap.templeLeft);
          out.addAll(VertexRoleMap.templeRight);
        }
      case 'chin':
        out.addAll(VertexRoleMap.jawLeft.take(4));
        out.addAll(VertexRoleMap.jawRight.take(4));
        out.addAll({152, 175, 199, 200, 17, 18});
      case 'cheekbone':
        out.addAll(VertexRoleMap.templeLeft);
        out.addAll(VertexRoleMap.templeRight);
        out.addAll(FaceWarpUtils.cheekboneLeft);
        out.addAll(FaceWarpUtils.cheekboneRight);
    }
    return out;
  }

  static double _edgeWeightFor(
    String toolKey,
    Offset base,
    double centerX,
    double fse,
  ) {
    if (toolKey != 'narrow_face') {
      return 1.0;
    }
    final halfFace = fse * 0.48;
    if (halfFace <= 1e-6) {
      return 0;
    }
    final lateral = (base.dx - centerX).abs();
    return math.pow((lateral / halfFace).clamp(0.0, 1.0), 0.72).toDouble();
  }

  static double _zoneWeightFor(String toolKey, double ny) {
    if (toolKey != 'narrow_face') {
      return 1.0;
    }
    var zoneWeight = 1.0;
    if (ny < 0.40) {
      zoneWeight = (0.42 + 0.58 * (ny / 0.40)).clamp(0.42, 1.0);
    }
    if (ny > 0.66) {
      zoneWeight *= (1.0 - (ny - 0.66) / 0.24).clamp(0.0, 1.0);
      zoneWeight = zoneWeight.clamp(0.30, 1.0);
    }
    return zoneWeight;
  }

  static double _tierWeightFor(String toolKey, int index) {
    if (toolKey != 'cheekbone') {
      return 1.0;
    }
    const ring = {
      207, 206, 203, 142, 126, 217, 427, 436, 426, 423, 266, 371,
    };
    if (FaceWarpUtils.cheekboneLeft.contains(index) ||
        FaceWarpUtils.cheekboneRight.contains(index)) {
      return 1.0;
    }
    if (ring.contains(index)) {
      return 0.65;
    }
    return 0.0;
  }

  static double _faceShortEdgePx(FaceMeshResult face, Size imageSize) {
    final bounds = FaceWarpUtils.landmarkBounds(
      face,
      imageSize,
      FaceWarpUtils.regionIndices(MeshRegion.faceOval).toSet(),
    );
    if (bounds == null || bounds.isEmpty) {
      return math.min(imageSize.width, imageSize.height);
    }
    return math.min(bounds.width, bounds.height);
  }

  static ({int x0, int y0, int x1, int y1}) _faceOvalBBox(
    FaceMeshResult face,
    Size imageSize,
  ) {
    final w = imageSize.width.round();
    final h = imageSize.height.round();
    var x0 = w;
    var y0 = h;
    var x1 = 0;
    var y1 = 0;
    for (final lm in face.landmarks) {
      if (!FaceWarpUtils.regionIndices(MeshRegion.faceOval).contains(lm.index)) {
        continue;
      }
      final x = (lm.normalized.dx * w).round();
      final y = (lm.normalized.dy * h).round();
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x);
      y1 = math.max(y1, y);
    }
    const pad = 8;
    return (
      x0: (x0 - pad).clamp(0, w - 1),
      y0: (y0 - pad).clamp(0, h - 1),
      x1: (x1 + pad).clamp(0, w - 1),
      y1: (y1 + pad).clamp(0, h - 1),
    );
  }

  static String _markdown(Map<String, dynamic> report) {
    final sb = StringBuffer('# Geometry Perception Audit\n\n');
    for (final tool in report['tools'] as List) {
      sb.writeln('## ${tool['toolKey']}\n');
      sb.writeln('Heatmap: ${tool['heatmapPath']}\n');
      sb.writeln('### Sensitivity\n');
      final table = tool['sensitivityTable'] as Map<String, Map<String, double>>;
      sb.writeln('| param | +10% | +20% | +30% |');
      sb.writeln('|-------|------|------|------|');
      for (final e in table.entries) {
        sb.writeln(
          '| ${e.key} | ${e.value['+10%']!.toStringAsFixed(1)} | '
          '${e.value['+20%']!.toStringAsFixed(1)} | ${e.value['+30%']!.toStringAsFixed(1)} |',
        );
      }
      sb.writeln('\n### Ranking\n');
      for (final r in tool['bottleneckRanking'] as List) {
        sb.writeln('${r['rank']}. **${r['parameter']}** — ~${r['estimatedVisualGainAt30pct']}% @+30%');
      }
      sb.writeln('');
    }
    return sb.toString();
  }
}

enum _VariantMode {
  baseline,
  sensitivity,
  expandRoi,
  boostWeights,
  addNeighbors,
}

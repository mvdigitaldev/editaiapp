import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset, Size;

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
import 'face_warp_mvp_calibration_diagnostic.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;
import 'face_warp_structural_pipeline.dart';

/// Auditoria: onde o ganho de maxDisplacementFse desaparece no pipeline.
abstract final class FaceWarpFseCompressionAudit {
  FaceWarpFseCompressionAudit._();

  static const toolFsePairs = {
    'chin': (oldFse: 0.06, newFse: 0.075),
    'cheekbone': (oldFse: 0.05, newFse: 0.07),
    'narrow_face': (oldFse: 0.06, newFse: 0.08),
  };

  static const sliderIntensities = [0.5, 0.8, 1.0];
  static const histThresholds = [0.25, 0.5, 1.0];
  static const histBins = [0.0, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 9999.0];

  static Future<Map<String, dynamic>> run({
    required List<FseAuditFaceInput> faces,
    String outputDirectory =
        '/Users/leonardo/Documents/Projetos/editaiapp/.cursor/fse-compression-audit',
  }) async {
    Directory(outputDirectory).createSync(recursive: true);
    final toolReports = <Map<String, dynamic>>[];

    for (final entry in toolFsePairs.entries) {
      final toolKey = entry.key;
      final oldFse = entry.value.oldFse;
      final newFse = entry.value.newFse;
      final roiIndices = _roiIndicesFor(toolKey);

      final perFace = <Map<String, dynamic>>[];
      for (final face in faces) {
        perFace.add(
          _auditFace(
            toolKey: toolKey,
            oldFse: oldFse,
            newFse: newFse,
            roiIndices: roiIndices,
            input: face,
          ),
        );
      }

      toolReports.add(_aggregateToolReport(
        toolKey: toolKey,
        oldFse: oldFse,
        newFse: newFse,
        roiVertexCount: roiIndices.length,
        perFace: perFace,
      ));
    }

    final report = {
      'phase': 'fse-compression-audit',
      'faceCount': faces.length,
      'tools': toolReports,
      'summaryTable': toolReports.map((t) => t['summaryRow']).toList(),
    };

    File('$outputDirectory/fse-compression-audit.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    File('$outputDirectory/fse-compression-audit.md')
        .writeAsStringSync(_markdown(report));

    return report;
  }

  static Map<String, dynamic> _auditFace({
    required String toolKey,
    required double oldFse,
    required double newFse,
    required Set<int> roiIndices,
    required FseAuditFaceInput input,
  }) {
    const engine = FaceMeshDeformationEngine();
    final mesh = input.mesh;
    final influence = FaceMatteRoi.buildInfluenceMap(
      face: input.face,
      imageSize: input.imageSize,
      lateralRadiusExpand: 0.07,
    );

    final fseCompare = <String, dynamic>{};
    for (final (label, fse) in [('old', oldFse), ('new', newFse)]) {
      FaceModelSpecification.maxDisplacementFseOverrides = {toolKey: fse};
      try {
        fseCompare[label] = _pipelineSnapshot(
          toolKey: toolKey,
          intensity: 1.0,
          engine: engine,
          face: input.face,
          mesh: mesh,
          imageSize: input.imageSize,
          influence: influence,
          roiIndices: roiIndices,
          sourceRgba: input.sourceRgba,
        );
      } finally {
        FaceModelSpecification.maxDisplacementFseOverrides = null;
      }
    }

    final sliderCurve = <Map<String, dynamic>>[];
    FaceModelSpecification.maxDisplacementFseOverrides = {toolKey: newFse};
    try {
      for (final intensity in sliderIntensities) {
        sliderCurve.add({
          'intensity': intensity,
          ..._pipelineSnapshot(
            toolKey: toolKey,
            intensity: intensity,
            engine: engine,
            face: input.face,
            mesh: mesh,
            imageSize: input.imageSize,
            influence: influence,
            roiIndices: roiIndices,
            sourceRgba: input.sourceRgba,
            includeRender: intensity == 1.0,
          ),
        });
      }
    } finally {
      FaceModelSpecification.maxDisplacementFseOverrides = null;
    }

    final oldSnap = fseCompare['old'] as Map<String, dynamic>;
    final newSnap = fseCompare['new'] as Map<String, dynamic>;

    return {
      'faceId': input.id,
      'isSynthetic': input.isSynthetic,
      'fseCompare': fseCompare,
      'fseGainPct': _stageGainTable(oldSnap, newSnap),
      'sliderCurveNewFse': sliderCurve,
      'sliderSaturation': _sliderSaturation(sliderCurve),
    };
  }

  static Map<String, dynamic> _pipelineSnapshot({
    required String toolKey,
    required double intensity,
    required FaceMeshDeformationEngine engine,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required InfluenceMap influence,
    required Set<int> roiIndices,
    required Uint8List sourceRgba,
    bool includeRender = true,
  }) {
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

    final stages = {
      'generator': _stageDetail(generatorField, mesh, roiIndices),
      'ace': _stageDetail(aceField, mesh, roiIndices),
      'phase9': _stageDetail(phase9Field, mesh, roiIndices),
      'effective': _stageDetail(effectiveField, mesh, roiIndices),
    };

    Map<String, dynamic>? render;
    if (includeRender) {
      render = _renderMetrics(
        toolKey: toolKey,
        intensity: intensity,
        engine: engine,
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        influence: influence,
        sourceRgba: sourceRgba,
        effectiveField: effectiveField,
        roiIndices: roiIndices,
      );
    }

    return {
      'intensity': intensity,
      'intent': _intentSnapshot(params, context),
      'stages': stages,
      if (render != null) 'render': render,
      'retention': {
        'aceFromGenerator': _retention(
          stages['generator']!['roiMax'] as double,
          stages['ace']!['roiMax'] as double,
        ),
        'phase9FromAce': _retention(
          stages['ace']!['roiMax'] as double,
          stages['phase9']!['roiMax'] as double,
        ),
        'effectiveFromPhase9': _retention(
          stages['phase9']!['roiMax'] as double,
          stages['effective']!['roiMax'] as double,
        ),
      },
      'avgSupportWeightRoi': _avgSupportWeightRoi(
        supportWeights,
        roiIndices,
        mesh,
      ),
    };
  }

  static Map<String, dynamic> _renderMetrics({
    required String toolKey,
    required double intensity,
    required FaceMeshDeformationEngine engine,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required InfluenceMap influence,
    required Uint8List sourceRgba,
    required ConstrainedVertexField effectiveField,
    required Set<int> roiIndices,
  }) {
    final w = imageSize.width.round();
    final h = imageSize.height.round();

    final vertexField = engine.composeVertexField(
      parameters: {toolKey: intensity},
      context: FaceAnatomyContext(face: face, imageSize: imageSize, mesh: mesh),
      mesh: mesh,
    );
    final payload = FaceMeshForwardPayload(
      mesh: mesh,
      vertexField: vertexField,
      influenceMap: influence,
    );
    final rendered = FaceMeshForwardWarp.apply(
      rgba: Uint8List.fromList(sourceRgba),
      width: w,
      height: h,
      payload: payload,
      runId: 'fse-audit-$toolKey',
    );

    final roi = _faceOvalBBox(face, imageSize);
    var maxPixelShift = 0.0;
    var sumShift = 0.0;
    var shiftedPixels = 0;
    var roiPixels = 0;
    var maxDeltaE = 0.0;
    var sumDeltaE = 0.0;

    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        roiPixels++;
        final o = (y * w + x) * 4;
        final dr = rendered[o] - sourceRgba[o];
        final dg = rendered[o + 1] - sourceRgba[o + 1];
        final db = rendered[o + 2] - sourceRgba[o + 2];
        if (dr == 0 && dg == 0 && db == 0) {
          continue;
        }
        shiftedPixels++;
        final de = _rgbDeltaE(
          sourceRgba[o],
          sourceRgba[o + 1],
          sourceRgba[o + 2],
          rendered[o],
          rendered[o + 1],
          rendered[o + 2],
        );
        sumDeltaE += de;
        if (de > maxDeltaE) {
          maxDeltaE = de;
        }
      }
    }

    // Pixel remap magnitude proxy via pair diff vs identity (same ROI).
    final pairVsSource = {
      'ssimGlobal': ImageQualityMetrics.ssim(sourceRgba, rendered, width: w, height: h),
      'deltaEGlobal': ImageQualityMetrics.deltaE2000Mean(sourceRgba, rendered),
      'roiShiftedPixelPct': roiPixels > 0 ? shiftedPixels / roiPixels : 0.0,
      'roiMaxDeltaE': maxDeltaE,
      'roiMeanDeltaE': shiftedPixels > 0 ? sumDeltaE / shiftedPixels : 0.0,
    };

    final effectiveMax = effectiveField.maxDisplacementMagnitude();
    return {
      ...pairVsSource,
      'effectiveMaxPx': effectiveMax,
      'renderRetentionVsEffectiveMax':
          effectiveMax > 1e-6 ? maxPixelShift / effectiveMax : 1.0,
      'forwardWarpLimitsField': false,
    };
  }

  static Map<String, dynamic> _stageDetail(
    ConstrainedVertexField field,
    TriMesh mesh,
    Set<int> roiIndices,
  ) {
    final count = FaceWarpFieldMetrics.safeVertexCount(field: field, mesh: mesh);
    final roiMags = <double>[];
    final hist = List<int>.filled(histBins.length - 1, 0);
    final above = {for (final t in histThresholds) '>${t}px': 0};

    for (final i in roiIndices) {
      if (i >= count) {
        continue;
      }
      final mag = field.displacementAt(i).distance;
      if (mag <= 0.05) {
        continue;
      }
      roiMags.add(mag);
      for (var b = 0; b < histBins.length - 1; b++) {
        if (mag >= histBins[b] && mag < histBins[b + 1]) {
          hist[b]++;
          break;
        }
      }
      for (final t in histThresholds) {
        if (mag > t) {
          above['>${t}px'] = above['>${t}px']! + 1;
        }
      }
    }

    roiMags.sort();
    final max = roiMags.isEmpty ? 0.0 : roiMags.last;
    final mean = roiMags.isEmpty
        ? 0.0
        : roiMags.reduce((a, b) => a + b) / roiMags.length;

    return {
      'roiMax': max,
      'roiMean': mean,
      'roiMovedCount': roiMags.length,
      'verticesAboveThreshold': above,
      'histogram': {
        'bins': histBins.sublist(0, histBins.length - 1),
        'counts': hist,
      },
      'histogramPct': hist
          .map((c) => roiMags.isEmpty ? 0.0 : c / roiMags.length)
          .toList(),
    };
  }

  static Map<String, dynamic> _intentSnapshot(
    Map<String, double> params,
    FaceAnatomyContext context,
  ) {
    final intents = AnatomicalIntentFactory.build(
      parameters: params,
      context: context,
    );
    if (intents.isEmpty) {
      return {};
    }
    final i = intents.first;
    return {
      'rawIntensity': i.rawIntensity,
      'magnitudeEaseOutCubic': i.magnitude,
    };
  }

  static double _avgSupportWeightRoi(
    Float32List weights,
    Set<int> roiIndices,
    TriMesh mesh,
  ) {
    var sum = 0.0;
    var n = 0;
    for (final i in roiIndices) {
      if (i >= weights.length) {
        continue;
      }
      sum += weights[i];
      n++;
    }
    return n > 0 ? sum / n : 0.0;
  }

  static Map<String, double> _stageGainTable(
    Map<String, dynamic> oldSnap,
    Map<String, dynamic> newSnap,
  ) {
    final stages = ['generator', 'ace', 'phase9', 'effective'];
    final out = <String, double>{};
    for (final s in stages) {
      final oldMax =
          ((oldSnap['stages'] as Map)[s] as Map)['roiMax'] as double;
      final newMax =
          ((newSnap['stages'] as Map)[s] as Map)['roiMax'] as double;
      out[s] = oldMax > 1e-6 ? (newMax / oldMax - 1) * 100 : 0.0;
    }
    final oldRender = oldSnap['render'] as Map<String, dynamic>?;
    final newRender = newSnap['render'] as Map<String, dynamic>?;
    if (oldRender != null && newRender != null) {
      final oldDe = oldRender['roiMeanDeltaE'] as double;
      final newDe = newRender['roiMeanDeltaE'] as double;
      out['roiMeanDeltaE'] =
          oldDe > 1e-6 ? (newDe / oldDe - 1) * 100 : 0.0;
    }
    return out;
  }

  static Map<String, dynamic> _sliderSaturation(
    List<Map<String, dynamic>> curve,
  ) {
    if (curve.length < 2) {
      return {'saturated': false};
    }
    final effMaxes = curve.map((c) {
      final stages = c['stages'] as Map<String, dynamic>;
      return (stages['effective'] as Map)['roiMax'] as double;
    }).toList();
    final at50 = effMaxes.first;
    final at100 = effMaxes.last;
    final ratio50vs100 = at100 > 1e-6 ? at50 / at100 : 1.0;
    final ratio80vs100 = at100 > 1e-6 ? effMaxes[1] / at100 : 1.0;
    return {
      'effectiveRoiMaxAt0.5': at50,
      'effectiveRoiMaxAt0.8': effMaxes[1],
      'effectiveRoiMaxAt1.0': at100,
      'ratio0.5vs1.0': ratio50vs100,
      'ratio0.8vs1.0': ratio80vs100,
      'saturatedAt0.5': ratio50vs100 > 0.95,
      'saturatedAt0.8': ratio80vs100 > 0.95,
      'flatSlider': ratio50vs100 > 0.95 && ratio80vs100 > 0.95,
    };
  }

  static Map<String, dynamic> _aggregateToolReport({
    required String toolKey,
    required double oldFse,
    required double newFse,
    required int roiVertexCount,
    required List<Map<String, dynamic>> perFace,
  }) {
    double avg(String stage, String metric) {
      var sum = 0.0;
      for (final f in perFace) {
        final oldStages =
            ((f['fseCompare'] as Map)['old'] as Map)['stages'] as Map;
        sum += (oldStages[stage] as Map)[metric] as double;
      }
      return sum / perFace.length;
    }

    double avgNew(String stage, String metric) {
      var sum = 0.0;
      for (final f in perFace) {
        final newStages =
            ((f['fseCompare'] as Map)['new'] as Map)['stages'] as Map;
        sum += (newStages[stage] as Map)[metric] as double;
      }
      return sum / perFace.length;
    }

    double avgGain(String stage) {
      var sum = 0.0;
      for (final f in perFace) {
        sum += (f['fseGainPct'] as Map)[stage] as double;
      }
      return sum / perFace.length;
    }

    double avgSlider(String key) {
      var sum = 0.0;
      for (final f in perFace) {
        sum += (f['sliderSaturation'] as Map)[key] as double;
      }
      return sum / perFace.length;
    }

    final internalGain = avgGain('effective');
    final genGain = avgGain('generator');
    final p9Gain = avgGain('phase9');

    double perceptualGain = 0;
    var perceptCount = 0;
    for (final f in perFace) {
      final g = f['fseGainPct'] as Map;
      if (g.containsKey('roiMeanDeltaE')) {
        perceptualGain += g['roiMeanDeltaE'] as double;
        perceptCount++;
      }
    }
    if (perceptCount > 0) {
      perceptualGain /= perceptCount;
    }

    final verdict = _verdict(
      toolKey: toolKey,
      genGain: genGain,
      aceGain: avgGain('ace'),
      p9Gain: p9Gain,
      effectiveGain: internalGain,
      perceptualGain: perceptualGain,
      roiVertexCount: roiVertexCount,
      avgSupportRoi: perFace
              .map((f) =>
                  ((f['fseCompare'] as Map)['new'] as Map)['avgSupportWeightRoi']
                      as double)
              .reduce((a, b) => a + b) /
          perFace.length,
      flatSlider: perFace.where((f) => (f['sliderSaturation'] as Map)['flatSlider'] == true).length,
      faceCount: perFace.length,
      chinGeneratorUsesFse: toolKey == 'chin',
    );

    return {
      'toolKey': toolKey,
      'oldFse': oldFse,
      'newFse': newFse,
      'roiVertexCount': roiVertexCount,
      'perFace': perFace,
      'summaryRow': {
        'tool': toolKey,
        'internalGainPct': internalGain.round(),
        'phase9GainPct': p9Gain.round(),
        'generatorGainPct': genGain.round(),
        'perceptualRoiGainPct': perceptualGain.round(),
        'avgSupportWeightRoi': (perFace
                    .map((f) =>
                        ((f['fseCompare'] as Map)['new'] as Map)[
                            'avgSupportWeightRoi'] as double)
                    .reduce((a, b) => a + b) /
                perFace.length)
            .toStringAsFixed(3),
        'flatSliderFaces': '${perFace.where((f) => (f['sliderSaturation'] as Map)['flatSlider'] == true).length}/${perFace.length}',
        'verdict': verdict,
      },
      'aggregateOldNew': {
        'oldEffectiveRoiMax': avg('effective', 'roiMax'),
        'newEffectiveRoiMax': avgNew('effective', 'roiMax'),
        'oldGeneratorRoiMax': avg('generator', 'roiMax'),
        'newGeneratorRoiMax': avgNew('generator', 'roiMax'),
      },
      'aggregateSlider': {
        'avgRatio0.5vs1.0': avgSlider('ratio0.5vs1.0'),
        'avgRatio0.8vs1.0': avgSlider('ratio0.8vs1.0'),
      },
      'verdict': verdict,
    };
  }

  static String _verdict({
    required String toolKey,
    required double genGain,
    required double aceGain,
    required double p9Gain,
    required double effectiveGain,
    required double perceptualGain,
    required int roiVertexCount,
    required double avgSupportRoi,
    required int flatSlider,
    required int faceCount,
    required bool chinGeneratorUsesFse,
  }) {
    if (toolKey == 'chin' && genGain.abs() < 2) {
      return 'D — generator não usa FSE; ganho só via clamp ACE (${aceGain.toStringAsFixed(0)}% ace, ${effectiveGain.toStringAsFixed(0)}% effective)';
    }
    if (genGain > 10 && aceGain < genGain * 0.5) {
      return 'D — ACE absorve parte do ganho do generator';
    }
    if (effectiveGain > 15 && perceptualGain.abs() < 10) {
      if (roiVertexCount <= 12) {
        return 'C — campo aumenta (+${effectiveGain.toStringAsFixed(0)}%) mas ROI tem $roiVertexCount vértices; diluição no render';
      }
      if (avgSupportRoi < 0.75) {
        return 'D — GeometricSupport (avg weight ${avgSupportRoi.toStringAsFixed(2)}) comprime effective vs phase9';
      }
      return 'C — campo aumenta mas área afetada pequena / poucos pixels mudam na ROI renderizada';
    }
    if (flatSlider >= faceCount * 0.7) {
      return 'D — slider aparenta saturar (effective@0.5 ≈ effective@1.0 em $flatSlider/$faceCount rostos)';
    }
    if (genGain < 5 && effectiveGain < 5) {
      return 'A — campo quase não aumenta (generator já no cap ou FSE irrelevante)';
    }
    if (p9Gain < effectiveGain * 0.7) {
      return 'B — Phase9 reduz retenção adicional';
    }
    return 'C+D — campo aumenta (+${effectiveGain.toStringAsFixed(0)}%) mas ROI pequena ($roiVertexCount verts) + diluição visual';
  }

  // --- pipeline helpers (mirror MVP calibration diagnostic) ---

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

        dx[index] += delta.dx;
        dy[index] += delta.dy;
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

  static Set<int> _verticesForZones(Set<dynamic> zones) {
    final out = <int>{};
    for (final zone in zones) {
      out.addAll(VertexRoleMap.landmarksFor(zone));
    }
    return out;
  }

  static Set<int> _roiIndicesFor(String toolKey) {
    return switch (toolKey) {
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

  static List<double> _interleave(Float32List dx, Float32List dy, int count) {
    final out = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      out[i * 2] = dx[i];
      out[i * 2 + 1] = dy[i];
    }
    return out;
  }

  static double _retention(double from, double to) {
    if (from <= 1e-9) {
      return to <= 1e-9 ? 1.0 : double.infinity;
    }
    return (to / from).clamp(0.0, 10.0);
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

  static double _rgbDeltaE(int r1, int g1, int b1, int r2, int g2, int b2) {
    final dr = (r1 - r2).abs().toDouble();
    final dg = (g1 - g2).abs().toDouble();
    final db = (b1 - b2).abs().toDouble();
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  static String _markdown(Map<String, dynamic> report) {
    final sb = StringBuffer('# FSE Compression Audit\n\n');
    sb.writeln('| Tool | Interno | Phase9 | Render ROI | Verdict |');
    sb.writeln('|------|---------|--------|------------|---------|');
    for (final row in report['summaryTable'] as List) {
      sb.writeln(
        '| ${row['tool']} | +${row['internalGainPct']}% | +${row['phase9GainPct']}% | '
        '${row['perceptualRoiGainPct']}% | ${row['verdict']} |',
      );
    }
    return sb.toString();
  }
}

class FseAuditFaceInput {
  const FseAuditFaceInput({
    required this.id,
    required this.face,
    required this.mesh,
    required this.imageSize,
    required this.sourceRgba,
    this.isSynthetic = false,
  });

  final String id;
  final FaceMeshResult face;
  final TriMesh mesh;
  final Size imageSize;
  final Uint8List sourceRgba;
  final bool isSynthetic;
}

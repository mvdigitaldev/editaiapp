import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/maps/influence_map.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/constrained_vertex_field.dart';

/// Modo de execução do renderer V3 (contrato Fase 0 — sem implementação).
enum FaceWarpRenderMode {
  preview,
  export,
  exportTile,
}

/// Parâmetros tunáveis do Geometric Support (valores por benchmark, não fixos).
class DeformationSupportParams {
  const DeformationSupportParams({
    this.supportWidthNorm = 0.12,
    this.falloffExponent = 2.0,
  });

  /// Largura normalizada da região de suporte além do contorno facial.
  final double supportWidthNorm;

  /// Expoente da curva de atenuação supportWeight → 0.
  final double falloffExponent;
}

/// Métricas do pipeline V3 (campo, coverage, imagem).
///
/// [requestedDisplacement], [effectiveDisplacement] e [displacementRetentionRatio]
/// referem-se ao **campo geométrico antes do backward remap/rasterizer**.
class FaceWarpBoundaryMetrics {
  const FaceWarpBoundaryMetrics({
    this.sourceCoverage,
    this.destinationCoverage,
    this.uncoveredRatio,
    this.displacementContinuityError,
    this.requestedDisplacement,
    this.effectiveDisplacement,
    this.displacementRetentionRatio,
    this.coverageRatio,
    this.lateralGhostPx,
    this.seamWidthPx,
    this.fallbackFillRatio,
    this.maxDisplacementPx,
    this.maxRigidDisplacementPx,
    this.minTriangleAreaRatio,
    this.backgroundPixelDelta,
    this.boundaryContinuityError,
    this.psnrGlobal,
    this.psnrFaceRoi,
    this.psnrSeamRoi,
    this.ghostRatio,
    this.previewExportPsnr,
  });

  /// Campo geométrico (pré-remap) — magnitude de coreDelta pós-ACE.
  final double? requestedDisplacement;

  /// Campo geométrico (pré-remap) — magnitude de effectiveDelta.
  final double? effectiveDisplacement;

  /// effective / requested; null quando requested == 0 (rigid/zero region).
  final double? displacementRetentionRatio;

  /// Gradiente do campo effectiveDelta atravessando CORE → SUPPORT → ZERO.
  final double? displacementContinuityError;

  /// Pós-remap — fração da fonte amostrada.
  final double? sourceCoverage;

  /// Pós-remap — fração do destino com correspondência geométrica válida.
  final double? destinationCoverage;

  /// Pós-remap — fração do destino sem correspondência válida.
  final double? uncoveredRatio;

  /// Legado/diagnóstico — meshHit / faceArea quando aplicável.
  final double? coverageRatio;

  final int? lateralGhostPx;
  final double? seamWidthPx;
  final double? fallbackFillRatio;
  final double? maxDisplacementPx;
  final double? maxRigidDisplacementPx;
  final double? minTriangleAreaRatio;
  final double? backgroundPixelDelta;
  final double? boundaryContinuityError;
  final double? psnrGlobal;
  final double? psnrFaceRoi;
  final double? psnrSeamRoi;
  final double? ghostRatio;
  final double? previewExportPsnr;

  Map<String, dynamic> toJson() => {
        'requestedDisplacement': requestedDisplacement,
        'effectiveDisplacement': effectiveDisplacement,
        'displacementRetentionRatio': displacementRetentionRatio,
        'displacementContinuityError': displacementContinuityError,
        'sourceCoverage': sourceCoverage,
        'destinationCoverage': destinationCoverage,
        'uncoveredRatio': uncoveredRatio,
        'coverageRatio': coverageRatio,
        'lateralGhostPx': lateralGhostPx,
        'seamWidthPx': seamWidthPx,
        'fallbackFillRatio': fallbackFillRatio,
        'maxDisplacementPx': maxDisplacementPx,
        'maxRigidDisplacementPx': maxRigidDisplacementPx,
        'minTriangleAreaRatio': minTriangleAreaRatio,
        'backgroundPixelDelta': backgroundPixelDelta,
        'boundaryContinuityError': boundaryContinuityError,
        'psnrGlobal': psnrGlobal,
        'psnrFaceRoi': psnrFaceRoi,
        'psnrSeamRoi': psnrSeamRoi,
        'ghostRatio': ghostRatio,
        'previewExportPsnr': previewExportPsnr,
      };
}

/// Entrada do renderer V3 (contrato — implementação na Fase 2).
class FaceWarpRenderRequest {
  const FaceWarpRenderRequest({
    required this.sourceRgba,
    required this.imageSize,
    required this.sourceMesh,
    required this.vertexField,
    required this.influenceMap,
    required this.parameters,
    required this.mode,
    this.personMask,
    this.supportParams = const DeformationSupportParams(),
    this.tileOriginX = 0,
    this.tileOriginY = 0,
  });

  final Uint8List sourceRgba;
  final Size imageSize;
  final TriMesh sourceMesh;
  final ConstrainedVertexField vertexField;
  final InfluenceMap influenceMap;
  final PersonMask? personMask;
  final Map<String, double> parameters;
  final FaceWarpRenderMode mode;
  final DeformationSupportParams supportParams;
  final double tileOriginX;
  final double tileOriginY;
}

/// Saída do renderer V3 (contrato — implementação na Fase 2).
class FaceWarpRenderResult {
  const FaceWarpRenderResult({
    required this.rgba,
    required this.metrics,
    this.coverage,
  });

  final Uint8List rgba;
  final Float32List? coverage;
  final FaceWarpBoundaryMetrics metrics;
}

/// Utilitários matemáticos do contrato V3.2 — campo geométrico (pré-remap).
abstract final class FaceWarpFieldMetrics {
  FaceWarpFieldMetrics._();

  static const meshVertexCount = 468;
  static const aceLandmarkCount = 478;
  static const irisLandmarkStart = 468;

  /// Índices mesh utilizáveis pelo renderer backward (0..467).
  static int rendererVertexCount(TriMesh mesh) =>
      mesh.vertices.length ~/ 2;

  /// Índices seguros para deformação: min(ACE slots, vértices mesh).
  static int safeVertexCount({
    required ConstrainedVertexField field,
    required TriMesh mesh,
  }) =>
      math.min(field.landmarkCount, rendererVertexCount(mesh));

  /// ‖coreDelta(v)‖
  static double requestedMagnitude(Offset coreDelta) => coreDelta.distance;

  /// effectiveDelta = coreDelta × supportWeight (preserva direção).
  static Offset effectiveDelta(Offset coreDelta, double supportWeight) =>
      Offset(
        coreDelta.dx * supportWeight,
        coreDelta.dy * supportWeight,
      );

  /// ‖effectiveDelta(v)‖
  static double effectiveMagnitude(Offset coreDelta, double supportWeight) =>
      effectiveDelta(coreDelta, supportWeight).distance;

  /// effective / requested; null se requested == 0 (sem divisão por zero).
  static double? retentionRatio(double requested, double effective) {
    if (requested == 0) {
      return null;
    }
    return effective / requested;
  }

  /// Verifica paralelismo de effectiveDelta com coreDelta (|cross| ≈ 0).
  static bool preservesDirection(Offset coreDelta, double supportWeight) {
    if (coreDelta.distance < 1e-9) {
      return true;
    }
    final eff = effectiveDelta(coreDelta, supportWeight);
    if (eff.distance < 1e-9) {
      return true;
    }
    final cross = coreDelta.dx * eff.dy - coreDelta.dy * eff.dx;
    return cross.abs() < 1e-6 * coreDelta.distance * eff.distance;
  }

  /// Interpolação baricêntrica: p = w0*v0 + w1*v1 + w2*v2.
  static Offset barycentricInterpolate(
    Offset v0,
    Offset v1,
    Offset v2,
    double w0,
    double w1,
    double w2,
  ) =>
      Offset(
        w0 * v0.dx + w1 * v1.dx + w2 * v2.dx,
        w0 * v0.dy + w1 * v1.dy + w2 * v2.dy,
      );

  /// Métricas de campo a partir de coreDelta e supportWeight por vértice.
  ///
  /// Medidas **antes** do backward remap. [supportWeights] length = safeVertexCount.
  static FaceWarpBoundaryMetrics computeFieldMetrics({
    required ConstrainedVertexField coreField,
    required TriMesh mesh,
    required Float32List supportWeights,
    Set<int>? rigidIndices,
  }) {
    final count = safeVertexCount(field: coreField, mesh: mesh);
    assert(supportWeights.length >= count);

    var maxRequested = 0.0;
    var maxEffective = 0.0;
    var maxRetention = 0.0;
    var retentionSamples = 0;
    var retentionSum = 0.0;
    var maxRigid = 0.0;

    for (var i = 0; i < count; i++) {
      final core = coreField.displacementAt(i);
      final requested = requestedMagnitude(core);
      final weight = supportWeights[i].clamp(0.0, 1.0);
      final effective = effectiveMagnitude(core, weight);

      if (requested > maxRequested) {
        maxRequested = requested;
      }
      if (effective > maxEffective) {
        maxEffective = effective;
      }

      final ratio = retentionRatio(requested, effective);
      if (ratio != null) {
        retentionSamples++;
        retentionSum += ratio;
        if (ratio > maxRetention) {
          maxRetention = ratio;
        }
      }

      if (rigidIndices != null && rigidIndices.contains(i)) {
        final rigidMag = effective;
        if (rigidMag > maxRigid) {
          maxRigid = rigidMag;
        }
      }
    }

    final avgRetention =
        retentionSamples > 0 ? retentionSum / retentionSamples : null;

    return FaceWarpBoundaryMetrics(
      requestedDisplacement: maxRequested,
      effectiveDisplacement: maxEffective,
      displacementRetentionRatio: avgRetention,
      maxDisplacementPx: maxRequested,
      maxRigidDisplacementPx: rigidIndices != null ? maxRigid : null,
      displacementContinuityError: computeDisplacementContinuityError(
        coreField: coreField,
        mesh: mesh,
        supportWeights: supportWeights,
      ),
    );
  }

  /// RMS do gradiente de ‖effectiveDelta‖ entre vértices adjacentes na malha.
  static double? computeDisplacementContinuityError({
    required ConstrainedVertexField coreField,
    required TriMesh mesh,
    required Float32List supportWeights,
  }) {
    final count = safeVertexCount(field: coreField, mesh: mesh);
    if (count <= 1 || mesh.indices.isEmpty) {
      return null;
    }

    final magnitudes = Float32List(count);
    for (var i = 0; i < count; i++) {
      final core = coreField.displacementAt(i);
      magnitudes[i] = effectiveMagnitude(core, supportWeights[i].clamp(0.0, 1.0));
    }

    var sumSq = 0.0;
    var edges = 0;
    final seen = <int>{};

    for (var t = 0; t < mesh.indices.length; t += 3) {
      final i0 = mesh.indices[t];
      final i1 = mesh.indices[t + 1];
      final i2 = mesh.indices[t + 2];
      if (i0 >= count || i1 >= count || i2 >= count) {
        continue;
      }
      for (final pair in [
        (i0, i1),
        (i1, i2),
        (i2, i0),
      ]) {
        final key = pair.$1 < pair.$2
            ? pair.$1 * count + pair.$2
            : pair.$2 * count + pair.$1;
        if (seen.contains(key)) {
          continue;
        }
        seen.add(key);
        final diff = magnitudes[pair.$1] - magnitudes[pair.$2];
        sumSq += diff * diff;
        edges++;
      }
    }

    if (edges == 0) {
      return null;
    }
    return math.sqrt(sumSq / edges);
  }

  /// Baseline Fase 0: supportWeight = 1.0 (Geometric Support ainda não existe).
  static FaceWarpBoundaryMetrics baselineFieldMetrics({
    required ConstrainedVertexField coreField,
    required TriMesh mesh,
    Set<int>? rigidIndices,
  }) {
    final count = safeVertexCount(field: coreField, mesh: mesh);
    final weights = Float32List(count)..fillRange(0, count, 1.0);
    return computeFieldMetrics(
      coreField: coreField,
      mesh: mesh,
      supportWeights: weights,
      rigidIndices: rigidIndices,
    );
  }
}

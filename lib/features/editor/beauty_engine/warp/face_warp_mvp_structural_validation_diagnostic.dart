import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset, Size;

import '../body_reshape/maps/influence_map.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/face_mesh_result.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/face_matte_roi.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'experimental/field_fold_audit_math.dart';
import 'experimental/global_jacobian_safety_gate.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

/// Validação estrutural estilo Phase 14 para uma ferramenta MVP calibrada.
abstract final class FaceWarpMvpStructuralValidationDiagnostic {
  FaceWarpMvpStructuralValidationDiagnostic._();

  static const _intensities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _epsilon = 0.10;
  static const _fdH = 2.0;
  static const _gridStep = 4;

  static Map<String, dynamic> validateTool({
    required String toolKey,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    PersonMask? personMask,
    List<double> intensities = _intensities,
    bool skipFieldDiagnostics = false,
  }) {
    const engine = FaceMeshDeformationEngine();
    final influence = FaceMatteRoi.buildInfluenceMap(
      face: face,
      imageSize: imageSize,
      personMask: personMask,
      lateralRadiusExpand: 0.07,
    );
    final sourceIndex = TriMeshSpatialIndex(
      mesh,
      imageWidth: imageSize.width,
      imageHeight: imageSize.height,
    );
    final roi = _roiFromMesh(mesh, imageSize);
    final vertexCount = mesh.vertices.length ~/ 2;
    final rows = <Map<String, dynamic>>[];
    var allPass = true;

    for (final intensity in intensities) {
      final built = _buildPipeline(
        engine: engine,
        toolKey: toolKey,
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        influence: influence,
        personMask: personMask,
        intensity: intensity,
      );

      final gate = GlobalJacobianSafetyGate.validate(
        mesh: mesh,
        originalDelta: built.effectiveDeltas,
        epsilon: _epsilon,
      );

      final applied = gate.outputDeltas;
      final diagnostic = skipFieldDiagnostics
          ? const <String, dynamic>{}
          : _diagnosticMetrics(
              sourceIndex: sourceIndex,
              roi: roi,
              vertexCount: vertexCount,
              deltas: applied,
            );

      final pass = gate.passed;
      if (!pass) {
        allPass = false;
      }

      rows.add({
        'intensity': intensity,
        'structuralPass': pass,
        'fallbackUsed': gate.fallbackUsed,
        'structuralChecks': gate.structuralChecks,
        'diagnostic': diagnostic,
        'constrainedVertexCount': gate.phase9Result.constrainedVertexCount,
        'constrainedTriangleCount': gate.phase9Result.constrainedTriangleCount,
      });
    }

    return {
      'toolKey': toolKey,
      'structuralPassAllIntensities': allPass,
      'rows': rows,
    };
  }

  static Map<String, dynamic> validateBatch({
    required String toolKey,
    required List<
        ({
          String id,
          String label,
          FaceMeshResult face,
          TriMesh mesh,
          Size imageSize,
          PersonMask? personMask,
        })> faces,
    String? outputDirectory,
    String runId = 'mvp-structural',
    bool skipFieldDiagnostics = false,
  }) {
    final perFace = <Map<String, dynamic>>[];
    var globalPass = true;

    for (final f in faces) {
      final result = validateTool(
        toolKey: toolKey,
        face: f.face,
        mesh: f.mesh,
        imageSize: f.imageSize,
        personMask: f.personMask,
        skipFieldDiagnostics: skipFieldDiagnostics,
      );
      if (result['structuralPassAllIntensities'] != true) {
        globalPass = false;
      }
      perFace.add({
        'id': f.id,
        'label': f.label,
        ...result,
      });
    }

    final summary = {
      'runId': runId,
      'toolKey': toolKey,
      'faceCount': faces.length,
      'structuralPassAllFaces': globalPass,
      'perFace': perFace,
    };

    if (outputDirectory != null) {
      Directory(outputDirectory).createSync(recursive: true);
      File('$outputDirectory/mvp-structural-$toolKey.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(summary),
      );
    }

    return summary;
  }

  static ({
    List<Offset> effectiveDeltas,
    int vertexCount,
  }) _buildPipeline({
    required FaceMeshDeformationEngine engine,
    required String toolKey,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required InfluenceMap influence,
    required PersonMask? personMask,
    required double intensity,
  }) {
    final vertexField = engine.composeVertexField(
      parameters: {toolKey: intensity},
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
      imageWidth: imageSize.width.round(),
      imageHeight: imageSize.height.round(),
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
      effectiveDeltas: effectiveDeltas,
      vertexCount: vertexCount,
    );
  }

  static Map<String, dynamic> _diagnosticMetrics({
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int vertexCount,
    required List<Offset> deltas,
  }) {
    final raw = _scanField(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      roi: roi,
      sameTriangleOnly: false,
      countBoundary: true,
    );
    final sameTri = _scanField(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      roi: roi,
      sameTriangleOnly: true,
      countBoundary: false,
    );
    return {
      'rawFieldFoldCount': raw.foldCount,
      'sameTriangleFieldFoldCount': sameTri.foldCount,
      'boundaryCrossingCount': raw.boundaryCrossings,
      'minTriangleJ': math.min(raw.minJ, sameTri.minJ),
    };
  }

  static ({
    double minJ,
    int foldCount,
    int boundaryCrossings,
  }) _scanField({
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required ({int x0, int y0, int x1, int y1}) roi,
    required bool sameTriangleOnly,
    required bool countBoundary,
  }) {
    final jValues = <double>[];
    var foldCount = 0;
    var boundaryCrossings = 0;

    for (var y = roi.y0 + _gridStep; y <= roi.y1 - _gridStep; y += _gridStep) {
      for (var x = roi.x0 + _gridStep; x <= roi.x1 - _gridStep; x += _gridStep) {
        final px = x + 0.5;
        final py = y + 0.5;

        if (countBoundary && !sameTriangleOnly) {
          final triP = sourceIndex.locateTriangleIndex(px, py);
          final triXm = sourceIndex.locateTriangleIndex(px - _fdH, py);
          final triXp = sourceIndex.locateTriangleIndex(px + _fdH, py);
          final triYm = sourceIndex.locateTriangleIndex(px, py - _fdH);
          final triYp = sourceIndex.locateTriangleIndex(px, py + _fdH);
          if (FieldFoldAuditMath.classifyStencil(
                triP: triP,
                triXm: triXm,
                triXp: triXp,
                triYm: triYm,
                triYp: triYp,
              ) ==
              FieldFoldStencilCategory.crossesTriangleBoundary) {
            boundaryCrossings++;
          }
        }

        final j = FieldFoldAuditMath.finiteDiffJacobian(
          sourceIndex: sourceIndex,
          deltas: deltas,
          vertexCount: vertexCount,
          px: px,
          py: py,
          h: _fdH,
          sameTriangleOnly: sameTriangleOnly,
        );
        if (j != null) {
          jValues.add(j);
          if (j < _epsilon) {
            foldCount++;
          }
        }
      }
    }

    jValues.sort();
    return (
      minJ: jValues.isEmpty ? 1.0 : jValues.first,
      foldCount: foldCount,
      boundaryCrossings: boundaryCrossings,
    );
  }

  static ({int x0, int y0, int x1, int y1}) _roiFromMesh(
    TriMesh mesh,
    Size imageSize,
  ) {
    final verts = mesh.vertices;
    var x0 = imageSize.width;
    var y0 = imageSize.height;
    var x1 = 0.0;
    var y1 = 0.0;
    for (var i = 0; i < verts.length; i += 2) {
      final x = verts[i];
      final y = verts[i + 1];
      if (x < x0) {
        x0 = x;
      }
      if (y < y0) {
        y0 = y;
      }
      if (x > x1) {
        x1 = x;
      }
      if (y > y1) {
        y1 = y;
      }
    }
    return (
      x0: x0.floor(),
      y0: y0.floor(),
      x1: x1.ceil(),
      y1: y1.ceil(),
    );
  }
}

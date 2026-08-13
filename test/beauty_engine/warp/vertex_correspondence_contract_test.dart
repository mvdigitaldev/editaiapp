import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_topology.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tri_mesh.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/constrained_vertex_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_render_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);

  TriMesh meshForSyntheticFace() {
    return const FaceMeshBuilder().build(syntheticFace(), imageSize);
  }

  group('478/468 vertex correspondence contract', () {
    test('mesh has 468 vertices; ACE field has 478 slots', () {
      final mesh = meshForSyntheticFace();
      final field = ConstrainedVertexField.zero();

      expect(FaceMeshTopology.landmarkCount, 468);
      expect(FaceMeshResult.expectedLandmarkCount, 478);
      expect(mesh.vertices.length ~/ 2, 468);
      expect(field.landmarkCount, 478);
    });

    test('landmarks 0..467 map to mesh vertices without RangeError', () {
      final mesh = meshForSyntheticFace();
      final displacements = Float32List(478 * 2);
      for (var i = 0; i < 468; i++) {
        displacements[i * 2] = 1.0;
        displacements[i * 2 + 1] = 0.5;
      }
      final field = ConstrainedVertexField(
        displacements: displacements,
        landmarkCount: 478,
      );
      final count = FaceWarpFieldMetrics.safeVertexCount(
        field: field,
        mesh: mesh,
      );
      expect(count, 468);

      for (var i = 0; i < count; i++) {
        expect(() => FaceWarpUtils.vertexAt(mesh, i), returnsNormally);
        expect(() => field.displacementAt(i), returnsNormally);
        expect(
          () => field.deformedVertex(mesh, i),
          returnsNormally,
        );
      }
    });

    test('iris landmarks 468..477 exist in ACE but not in mesh vertices', () {
      final mesh = meshForSyntheticFace();
      final field = ConstrainedVertexField.zero();

      for (final i in FaceWarpUtils.irisLandmarkIndices) {
        expect(i, greaterThanOrEqualTo(468));
        expect(i, lessThan(478));
        expect(FaceWarpUtils.vertexAt(mesh, i), isNull);
        expect(field.displacementAt(i), Offset.zero);
      }

      expect(
        FaceWarpFieldMetrics.safeVertexCount(field: field, mesh: mesh),
        468,
      );
    });

    test('displacementAt out of ACE range returns zero', () {
      final field = ConstrainedVertexField.zero();
      expect(field.displacementAt(-1), Offset.zero);
      expect(field.displacementAt(478), Offset.zero);
      expect(field.displacementAt(999), Offset.zero);
    });
  });

  group('baricentric interpolation contract', () {
    test('weights sum to 1 reproduce vertex positions', () {
      const v0 = Offset(0, 0);
      const v1 = Offset(10, 0);
      const v2 = Offset(0, 10);

      expect(
        FaceWarpFieldMetrics.barycentricInterpolate(v0, v1, v2, 1, 0, 0),
        v0,
      );
      expect(
        FaceWarpFieldMetrics.barycentricInterpolate(v0, v1, v2, 0, 1, 0),
        v1,
      );
      expect(
        FaceWarpFieldMetrics.barycentricInterpolate(v0, v1, v2, 0, 0, 1),
        v2,
      );
      final centroid = FaceWarpFieldMetrics.barycentricInterpolate(
        v0,
        v1,
        v2,
        1 / 3,
        1 / 3,
        1 / 3,
      );
      expect(centroid.dx, closeTo(10 / 3, 1e-9));
      expect(centroid.dy, closeTo(10 / 3, 1e-9));
    });

    test('identity when all displacements are zero', () {
      final mesh = meshForSyntheticFace();
      final field = ConstrainedVertexField.zero();
      final count = FaceWarpFieldMetrics.safeVertexCount(
        field: field,
        mesh: mesh,
      );

      for (var i = 0; i < count; i++) {
        final base = FaceWarpUtils.vertexAt(mesh, i)!;
        final deformed = field.deformedVertex(mesh, i);
        expect(deformed.dx, closeTo(base.dx, 1e-6));
        expect(deformed.dy, closeTo(base.dy, 1e-6));
      }

      final metrics = FaceWarpFieldMetrics.baselineFieldMetrics(
        coreField: field,
        mesh: mesh,
      );
      expect(metrics.requestedDisplacement, 0);
      expect(metrics.effectiveDisplacement, 0);
      expect(metrics.displacementRetentionRatio, isNull);
    });
  });

  group('Geometric Support math contract (direction + retention)', () {
    test('effectiveDelta = coreDelta × supportWeight preserves direction', () {
      const core = Offset(4, -2);
      for (final w in [1.0, 0.8, 0.5, 0.2, 0.01]) {
        expect(
          FaceWarpFieldMetrics.preservesDirection(core, w),
          isTrue,
          reason: 'weight=$w',
        );
        final eff = FaceWarpFieldMetrics.effectiveDelta(core, w);
        expect(eff.dx, closeTo(core.dx * w, 1e-9));
        expect(eff.dy, closeTo(core.dy * w, 1e-9));
      }
    });

    test('retentionRatio is null when requestedDisplacement == 0', () {
      expect(FaceWarpFieldMetrics.retentionRatio(0, 0), isNull);
      expect(FaceWarpFieldMetrics.retentionRatio(0, 5), isNull);
      expect(FaceWarpFieldMetrics.retentionRatio(3, 1.5), closeTo(0.5, 1e-9));
    });

    test('baseline weight=1 yields retentionRatio ≈ 1 where displacement > 0',
        () {
      final mesh = meshForSyntheticFace();
      final displacements = Float32List(478 * 2);
      displacements[132 * 2] = -5;
      final field = ConstrainedVertexField(
        displacements: displacements,
        landmarkCount: 478,
      );
      final metrics = FaceWarpFieldMetrics.baselineFieldMetrics(
        coreField: field,
        mesh: mesh,
      );
      expect(metrics.requestedDisplacement, closeTo(5, 1e-6));
      expect(metrics.effectiveDisplacement, closeTo(5, 1e-6));
      expect(metrics.displacementRetentionRatio, closeTo(1.0, 1e-6));
    });
  });
}

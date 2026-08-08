import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../filters/face/face_warp_utils.dart';
import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import '../../models/tri_mesh.dart';
import '../../mesh/mesh_topology.dart';
import 'anatomical_intent.dart';
import 'anatomical_zone.dart';
import 'constrained_vertex_field.dart';
import 'face_model_specification.dart';
import 'pilot_warp_displacement.dart';
import 'vertex_role_map.dart';

/// Anatomical Constraint Engine — resolve intents em deslocamentos permitidos.
///
/// Ordem fixa: resolver zona → pins → combinar → clamp → anti-fold → pins finais.
class AnatomicalConstraintEngine {
  const AnatomicalConstraintEngine({
    this.semiRigidWeight = 0.5,
    this.minTriangleAreaRatio = 0.35,
    this.antiFoldIterations = 2,
  });

  final double semiRigidWeight;
  final double minTriangleAreaRatio;
  final int antiFoldIterations;

  ConstrainedVertexField compose({
    required List<AnatomicalIntent> intents,
    required FaceAnatomyContext context,
  }) {
    if (intents.isEmpty) {
      return ConstrainedVertexField.zero(
        landmarkCount: FaceMeshResult.expectedLandmarkCount,
      );
    }

    final count = FaceMeshResult.expectedLandmarkCount;
    final dx = Float32List(count);
    final dy = Float32List(count);
    final priority = Int32List(count)..fillRange(0, count, -1);

    final fse = _faceShortEdgePx(context.face, context.imageSize);
    final effectiveScale = context.intensityScale.clamp(0.0, 1.0);

    final sorted = List<AnatomicalIntent>.of(intents)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    for (final intent in sorted) {
      if (intent.magnitude <= 1e-6) {
        continue;
      }
      final spec = FaceModelSpecification.forKey(intent.toolKey);
      if (spec == null) {
        continue;
      }
      _applyIntent(
        intent: intent,
        spec: spec,
        context: context,
        fse: fse,
        effectiveScale: effectiveScale,
        dx: dx,
        dy: dy,
        priority: priority,
      );
    }

    var clampedVertices = 0;
    var rigidPinned = 0;

    for (final intent in sorted) {
      final spec = FaceModelSpecification.forKey(intent.toolKey);
      if (spec == null) {
        continue;
      }
      clampedVertices += _clampBySpec(
        spec: spec,
        fse: fse,
        effectiveScale: effectiveScale,
        dx: dx,
        dy: dy,
        count: count,
      );
      rigidPinned += _enforceRigid(spec, dx, dy);
    }

    for (final index in VertexRoleMap.oralCavity) {
      if (index < count) {
        if (dx[index] != 0 || dy[index] != 0) {
          rigidPinned++;
        }
        dx[index] = 0;
        dy[index] = 0;
      }
    }

    final foldReduced = _antiFold(context.mesh, dx, dy, count);

    for (final intent in sorted) {
      final spec = FaceModelSpecification.forKey(intent.toolKey);
      if (spec == null) {
        continue;
      }
      rigidPinned += _enforceRigid(spec, dx, dy);
    }
    for (final index in VertexRoleMap.oralCavity) {
      if (index < count) {
        dx[index] = 0;
        dy[index] = 0;
      }
    }

    return ConstrainedVertexField(
      displacements: Float32List.fromList(_interleave(dx, dy, count)),
      landmarkCount: count,
      clampedVertices: clampedVertices,
      foldReducedTriangles: foldReduced,
      rigidPinnedVertices: rigidPinned,
    );
  }

  void _applyIntent({
    required AnatomicalIntent intent,
    required FaceToolSpecification spec,
    required FaceAnatomyContext context,
    required double fse,
    required double effectiveScale,
    required Float32List dx,
    required Float32List dy,
    required Int32List priority,
  }) {
    final center = FaceWarpUtils.faceCenter(context.face, context.imageSize) ??
        Offset(context.imageSize.width * 0.5, context.imageSize.height * 0.5);

    final zoneVertices = _verticesForZones(intent.resolvedZones);
    final magnitude = intent.magnitude.clamp(0.0, 1.0) * effectiveScale;

    for (final index in zoneVertices) {
      final role = _roleForVertex(index, spec);
      if (role == VertexRole.rigid) {
        continue;
      }

      final base = FaceWarpUtils.vertexAt(context.mesh, index);
      if (base == null) {
        continue;
      }

      final delta = _deltaForMode(
        toolKey: intent.toolKey,
        mode: intent.mode,
        spec: spec,
        base: base,
        center: center,
        axis: intent.axis,
        magnitude: magnitude,
        rawIntensity: intent.rawIntensity ?? intent.magnitude,
        fse: fse,
        context: context,
        index: index,
      );

      var weight = 1.0;
      if (role == VertexRole.semiRigid) {
        weight = semiRigidWeight;
      }

      final pdx = delta.dx * weight;
      final pdy = delta.dy * weight;

      if (priority[index] < intent.priority) {
        dx[index] = pdx;
        dy[index] = pdy;
        priority[index] = intent.priority;
      } else if (priority[index] == intent.priority) {
        dx[index] += pdx;
        dy[index] += pdy;
      } else {
        // Conflito: média ponderada se direções opostas.
        final dot = dx[index] * pdx + dy[index] * pdy;
        if (dot < 0) {
          dx[index] = (dx[index] + pdx) * 0.5;
          dy[index] = (dy[index] + pdy) * 0.5;
        }
      }
    }
  }

  Offset _deltaForMode({
    required String toolKey,
    required DeformationMode mode,
    required FaceToolSpecification spec,
    required Offset base,
    required Offset center,
    required Offset axis,
    required double magnitude,
    required double rawIntensity,
    required double fse,
    required FaceAnatomyContext context,
    required int index,
  }) {
    switch (mode) {
      case DeformationMode.pilot:
        return PilotWarpDisplacement.deltaFor(
          toolKey: toolKey,
          landmarkIndex: index,
          base: base,
          spec: spec,
          face: context.face,
          mesh: context.mesh,
          imageSize: context.imageSize,
          magnitude: magnitude,
          rawIntensity: rawIntensity,
          linkEyes: context.linkEyes,
          fse: fse,
        );

      case DeformationMode.radialInward:
        final maxPx = (spec.maxDisplacementFse ?? 0) * fse * magnitude;
        if (maxPx <= 0) {
          return Offset.zero;
        }
        final toCenter = center - base;
        final dist = toCenter.distance;
        if (dist < 1e-6) {
          return Offset.zero;
        }
        return toCenter / dist * maxPx;

      case DeformationMode.radialOutward:
        final maxPx = (spec.maxDisplacementFse ?? 0) * fse * magnitude;
        if (maxPx <= 0) {
          return Offset.zero;
        }
        final fromCenter = base - center;
        final dist = fromCenter.distance;
        if (dist < 1e-6) {
          return Offset.zero;
        }
        return fromCenter / dist * maxPx;

      case DeformationMode.translate:
        final maxPx = (spec.maxDisplacementFse ?? 0) * fse * magnitude;
        if (maxPx <= 0 || axis.distanceSquared < 1e-12) {
          return Offset.zero;
        }
        final dir = axis / axis.distance;
        return dir * maxPx;

      case DeformationMode.scale:
        final minS = spec.minScale ?? 1.0;
        final maxS = spec.maxScale ?? 1.0;
        final scale = minS + (maxS - minS) * magnitude;
        final pivot = center;
        return pivot + (base - pivot) * scale - base;

      case DeformationMode.rotate:
        final maxDeg = spec.maxRotationDegrees ?? 0;
        if (maxDeg <= 0) {
          return Offset.zero;
        }
        final radians = maxDeg * magnitude * math.pi / 180.0;
        final pivot = center;
        final v = base - pivot;
        final cos = math.cos(radians);
        final sin = math.sin(radians);
        final rotated = Offset(
          v.dx * cos - v.dy * sin,
          v.dx * sin + v.dy * cos,
        );
        return pivot + rotated - base;
    }
  }

  VertexRole _roleForVertex(int index, FaceToolSpecification spec) {
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
    for (final zone in spec.freeZones) {
      if (VertexRoleMap.landmarksFor(zone).contains(index)) {
        return VertexRole.free;
      }
    }
    for (final zone in spec.primaryZones) {
      if (VertexRoleMap.landmarksFor(zone).contains(index)) {
        return VertexRole.free;
      }
    }
    return VertexRole.rigid;
  }

  Set<int> _verticesForZones(Set<AnatomicalZone> zones) {
    final out = <int>{};
    for (final zone in zones) {
      out.addAll(VertexRoleMap.landmarksFor(zone));
    }
    return out;
  }

  int _clampBySpec({
    required FaceToolSpecification spec,
    required double fse,
    required double effectiveScale,
    required Float32List dx,
    required Float32List dy,
    required int count,
  }) {
    var clamped = 0;
    final zoneVertices = _verticesForZones({
      ...spec.primaryZones,
      ...spec.freeZones,
      ...spec.semiRigidZones,
    });

    for (final index in zoneVertices) {
      if (index >= count) {
        continue;
      }
      final maxPx = _maxPxForSpec(spec, fse, effectiveScale);
      if (maxPx <= 0) {
        continue;
      }
      final mag = math.sqrt(dx[index] * dx[index] + dy[index] * dy[index]);
      if (mag > maxPx) {
        final s = maxPx / mag;
        dx[index] *= s;
        dy[index] *= s;
        clamped++;
      }
    }
    return clamped;
  }

  double _maxPxForSpec(
    FaceToolSpecification spec,
    double fse,
    double effectiveScale,
  ) {
    if (spec.maxDisplacementFse != null) {
      return spec.maxDisplacementFse! * fse * effectiveScale;
    }
    if (spec.maxScale != null && spec.minScale != null) {
      return (spec.maxScale! - 1.0).abs() * fse * effectiveScale;
    }
    return 0;
  }

  int _enforceRigid(
    FaceToolSpecification spec,
    Float32List dx,
    Float32List dy,
  ) {
    var pinned = 0;
    for (final zone in spec.rigidZones) {
      for (final index in VertexRoleMap.landmarksFor(zone)) {
        if (dx[index] != 0 || dy[index] != 0) {
          pinned++;
        }
        dx[index] = 0;
        dy[index] = 0;
      }
    }
    return pinned;
  }

  int _antiFold(
    TriMesh mesh,
    Float32List dx,
    Float32List dy,
    int count,
  ) {
    var reduced = 0;
    final indices = mesh.indices;
    if (indices.isEmpty) {
      return 0;
    }

    for (var iter = 0; iter < antiFoldIterations; iter++) {
      for (var t = 0; t < indices.length; t += 3) {
        final a = indices[t];
        final b = indices[t + 1];
        final c = indices[t + 2];
        if (a >= count || b >= count || c >= count) {
          continue;
        }

        final origArea = _triangleArea(
          _pos(mesh, a),
          _pos(mesh, b),
          _pos(mesh, c),
        );
        if (origArea < 1e-6) {
          continue;
        }

        final newArea = _triangleArea(
          _pos(mesh, a) + Offset(dx[a], dy[a]),
          _pos(mesh, b) + Offset(dx[b], dy[b]),
          _pos(mesh, c) + Offset(dx[c], dy[c]),
        );

        final minArea = origArea * minTriangleAreaRatio;
        if (newArea >= minArea) {
          continue;
        }

        final scale = math.sqrt(minArea / math.max(newArea, 1e-12));
        final factor = scale.clamp(0.0, 1.0);
        for (final v in [a, b, c]) {
          dx[v] *= factor;
          dy[v] *= factor;
        }
        reduced++;
      }
    }
    return reduced;
  }

  Offset _pos(TriMesh mesh, int index) {
    return Offset(
      mesh.vertices[index * 2],
      mesh.vertices[index * 2 + 1],
    );
  }

  double _triangleArea(Offset a, Offset b, Offset c) {
    return ((b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx))
            .abs() *
        0.5;
  }

  double _faceShortEdgePx(FaceMeshResult face, Size imageSize) {
    final oval = MeshTopology.faceRegionLandmarks[MeshRegion.faceOval];
    if (oval == null) {
      return math.min(imageSize.width, imageSize.height);
    }
    final bounds = FaceWarpUtils.landmarkBounds(face, imageSize, oval);
    if (bounds == null || bounds.isEmpty) {
      return math.min(imageSize.width, imageSize.height);
    }
    return math.min(bounds.width, bounds.height);
  }

  Float32List _interleave(Float32List dx, Float32List dy, int count) {
    final out = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      out[i * 2] = dx[i];
      out[i * 2 + 1] = dy[i];
    }
    return out;
  }

  /// Papel efetivo de um landmark para debug/UI (ferramenta ativa).
  static VertexRole debugRoleFor({
    required int landmarkIndex,
    required FaceToolSpecification? spec,
  }) {
    if (VertexRoleMap.oralCavity.contains(landmarkIndex)) {
      return VertexRole.rigid;
    }
    if (spec == null) {
      return VertexRoleMap.defaultRole.entries
              .where((e) => VertexRoleMap.landmarksFor(e.key).contains(landmarkIndex))
              .map((e) => e.value)
              .firstOrNull ??
          VertexRole.free;
    }
    final engine = const AnatomicalConstraintEngine();
    return engine._roleForVertex(landmarkIndex, spec);
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}

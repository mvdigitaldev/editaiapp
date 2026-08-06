import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../maps/matte_preprocessor.dart';
import '../maps/protection_maps.dart';
import '../maps/signed_distance_field.dart';
import '../models/body_frame_assets.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import '../models/body_reshape_request.dart';
import 'adaptive_body_mesh.dart';
import 'constrained_triangulator.dart';
import 'mesh_resolution_profile.dart';

/// Gera malha corporal densa adaptativa a partir de matte + landmarks.
class AdaptiveMeshGenerator {
  const AdaptiveMeshGenerator({
    this.preprocessor = const MattePreprocessor(),
    this.triangulator = const ConstrainedTriangulator(),
  });

  final MattePreprocessor preprocessor;
  final ConstrainedTriangulator triangulator;

  /// Multiplicadores < 1 → mais densidade (células menores).
  static const regionDensityFactors = <BodyRegion, double>{
    BodyRegion.waist: 0.5,
    BodyRegion.hip: 0.52,
    BodyRegion.chest: 0.48,
    BodyRegion.butt: 0.48,
    BodyRegion.leftArm: 0.50,
    BodyRegion.rightArm: 0.50,
    BodyRegion.leftForearm: 0.52,
    BodyRegion.rightForearm: 0.52,
    BodyRegion.leftThigh: 0.50,
    BodyRegion.rightThigh: 0.50,
    BodyRegion.leftCalf: 0.52,
    BodyRegion.rightCalf: 0.52,
    BodyRegion.shoulders: 0.55,
    BodyRegion.neck: 0.58,
    BodyRegion.torso: 0.85,
  };

  AdaptiveBodyMesh generate({
    required BodyFrameAssets assets,
    required Size imageSize,
    WarpQualityProfile qualityProfile = WarpQualityProfile.preview,
  }) {
    final profile = MeshResolutionProfile.fromQuality(qualityProfile, imageSize);
    final matte = assets.personMatte;
    final processed = matte == null || matte.isEmpty
        ? null
        : preprocessor.process(matte, imageSize: imageSize);

    final protection = processed?.protection;
    final sdf = processed?.sdf;
    final bounds = _resolveBounds(
      assets: assets,
      imageSize: imageSize,
      processed: processed,
    );

    final seeded = <Offset>[
      ..._landmarkSeeds(assets, imageSize),
      if (processed != null)
        ..._contourSeeds(
          processed: processed,
          imageSize: imageSize,
          spacingPx: profile.contourSpacingPx,
        ),
    ];

    final triangulation = triangulator.triangulate(
      bounds: bounds.inflate(profile.baseCellPx),
      isInside: (point) => _isInside(
        point: point,
        imageSize: imageSize,
        protection: protection,
        assets: assets,
        bounds: bounds,
      ),
      cellSizeAt: (point) => _cellSizeAt(
        point: point,
        imageSize: imageSize,
        profile: profile,
        sdf: sdf,
        assets: assets,
      ),
      maxVertices: profile.maxVertices,
      seededPoints: seeded,
    );

    return _assembleMesh(
      triangulation: triangulation,
      imageSize: imageSize,
      profile: profile,
      assets: assets,
      protection: protection,
      bounds: bounds,
    );
  }

  AdaptiveBodyMesh _assembleMesh({
    required TriangulationResult triangulation,
    required Size imageSize,
    required MeshResolutionProfile profile,
    required BodyFrameAssets assets,
    required ProtectionMaps? protection,
    required Rect bounds,
  }) {
    final vertexCount = triangulation.vertexCount;
    final uvs = Float32List(vertexCount * 2);
    final weights = Float32List(vertexCount);
    final regionCodes = Int32List(vertexCount);
    final invW = imageSize.width > 0 ? 1.0 / imageSize.width : 0.0;
    final invH = imageSize.height > 0 ? 1.0 / imageSize.height : 0.0;

    for (var i = 0; i < vertexCount; i++) {
      final x = triangulation.vertices[i * 2];
      final y = triangulation.vertices[i * 2 + 1];
      final nx = (x * invW).clamp(0.0, 1.0);
      final ny = (y * invH).clamp(0.0, 1.0);
      uvs[i * 2] = nx;
      uvs[i * 2 + 1] = ny;
      weights[i] = protection?.sampleWarpWeight(nx, ny) ?? 0.65;
      regionCodes[i] =
          _classifyRegion(Offset(x, y), assets, imageSize).index;
    }

    final regionTriangles = <BodyRegion, List<int>>{};
    for (var t = 0; t < triangulation.indices.length; t += 3) {
      final a = triangulation.indices[t];
      final b = triangulation.indices[t + 1];
      final c = triangulation.indices[t + 2];
      final region = _majorityRegion(regionCodes, a, b, c);
      regionTriangles.putIfAbsent(region, () => []).addAll([a, b, c]);
    }

    return AdaptiveBodyMesh(
      vertices: triangulation.vertices,
      uvs: uvs,
      indices: triangulation.indices,
      weights: weights,
      vertexRegionCodes: regionCodes,
      regionTriangleIndices: {
        for (final entry in regionTriangles.entries)
          entry.key: Uint32List.fromList(entry.value),
      },
      profile: profile,
      imageSize: imageSize,
      bounds: bounds,
      isPartial: assets.isPartial,
    );
  }

  Rect _resolveBounds({
    required BodyFrameAssets assets,
    required Size imageSize,
    required ProcessedPersonMatte? processed,
  }) {
    if (processed != null && !processed.boundingRegion.isEmpty) {
      final r = processed.boundingRegion;
      return Rect.fromLTRB(
        r.left * imageSize.width,
        r.top * imageSize.height,
        r.right * imageSize.width,
        r.bottom * imageSize.height,
      );
    }

    if (assets.landmarks.isEmpty) {
      return Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final landmark in assets.landmarks.values) {
      final x = landmark.normalized.dx * imageSize.width;
      final y = landmark.normalized.dy * imageSize.height;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    final pad = math.min(imageSize.width, imageSize.height) * 0.08;
    return Rect.fromLTRB(
      math.max(0, minX - pad),
      math.max(0, minY - pad),
      math.min(imageSize.width, maxX + pad),
      math.min(imageSize.height, maxY + pad),
    );
  }

  List<Offset> _landmarkSeeds(BodyFrameAssets assets, Size imageSize) {
    return [
      for (final landmark in assets.landmarks.values)
        Offset(
          landmark.normalized.dx * imageSize.width,
          landmark.normalized.dy * imageSize.height,
        ),
    ];
  }

  List<Offset> _contourSeeds({
    required ProcessedPersonMatte processed,
    required Size imageSize,
    required double spacingPx,
  }) {
    final contour = processed.contour;
    final width = processed.matte.width;
    final height = processed.matte.height;
    if (contour.isEmpty || width <= 0 || height <= 0) {
      return const [];
    }

    final scaleX = imageSize.width / math.max(width - 1, 1);
    final scaleY = imageSize.height / math.max(height - 1, 1);
    final step = math.max(1, (spacingPx / math.max(scaleX, scaleY)).round());
    final seeds = <Offset>[];

    for (var y = 0; y < height; y += step) {
      for (var x = 0; x < width; x += step) {
        if (contour[y * width + x] == 0) {
          continue;
        }
        seeds.add(Offset(x * scaleX, y * scaleY));
      }
    }
    return seeds;
  }

  bool _isInside({
    required Offset point,
    required Size imageSize,
    required ProtectionMaps? protection,
    required BodyFrameAssets assets,
    required Rect bounds,
  }) {
    if (!bounds.inflate(2).contains(point)) {
      return false;
    }
    if (protection != null && !protection.isEmpty) {
      final nx = (point.dx / imageSize.width).clamp(0.0, 1.0);
      final ny = (point.dy / imageSize.height).clamp(0.0, 1.0);
      return protection.sampleWarpWeight(nx, ny) > 0.02 ||
          protection.sdf.sampleNormalized(nx, ny) <= 0;
    }

    // Fallback sem matte: cápsula ao redor dos landmarks.
    return _distanceToPoseSkeleton(point, assets, imageSize) <=
        math.min(imageSize.width, imageSize.height) * 0.085;
  }

  double _cellSizeAt({
    required Offset point,
    required Size imageSize,
    required MeshResolutionProfile profile,
    required SignedDistanceField? sdf,
    required BodyFrameAssets assets,
  }) {
    final region = _classifyRegion(point, assets, imageSize);
    final regionFactor = regionDensityFactors[region] ?? 0.85;
    var cell = profile.baseCellPx * regionFactor;

    if (sdf != null && !sdf.isEmpty) {
      final nx = (point.dx / imageSize.width).clamp(0.0, 1.0);
      final ny = (point.dy / imageSize.height).clamp(0.0, 1.0);
      final distance = sdf.sampleNormalized(nx, ny).abs();
      // Mais densidade próximo ao contorno.
      if (distance < profile.baseCellPx * 1.5) {
        cell *= 0.55;
      } else if (distance < profile.baseCellPx * 3) {
        cell *= 0.75;
      }
    }

    return cell.clamp(profile.minCellPx, profile.baseCellPx);
  }

  BodyRegion _classifyRegion(
    Offset point,
    BodyFrameAssets assets,
    Size imageSize,
  ) {
    Offset? px(BodyJoint joint) {
      final landmark = assets.landmark(joint);
      if (landmark == null) {
        return null;
      }
      return Offset(
        landmark.normalized.dx * imageSize.width,
        landmark.normalized.dy * imageSize.height,
      );
    }

    final segments = <(BodyRegion, Offset, Offset)>[
      if (px(BodyJoint.leftShoulder) != null && px(BodyJoint.leftElbow) != null)
        (BodyRegion.leftArm, px(BodyJoint.leftShoulder)!, px(BodyJoint.leftElbow)!),
      if (px(BodyJoint.leftElbow) != null && px(BodyJoint.leftWrist) != null)
        (
          BodyRegion.leftForearm,
          px(BodyJoint.leftElbow)!,
          px(BodyJoint.leftWrist)!
        ),
      if (px(BodyJoint.rightShoulder) != null &&
          px(BodyJoint.rightElbow) != null)
        (
          BodyRegion.rightArm,
          px(BodyJoint.rightShoulder)!,
          px(BodyJoint.rightElbow)!
        ),
      if (px(BodyJoint.rightElbow) != null && px(BodyJoint.rightWrist) != null)
        (
          BodyRegion.rightForearm,
          px(BodyJoint.rightElbow)!,
          px(BodyJoint.rightWrist)!
        ),
      if (px(BodyJoint.leftHip) != null && px(BodyJoint.leftKnee) != null)
        (BodyRegion.leftThigh, px(BodyJoint.leftHip)!, px(BodyJoint.leftKnee)!),
      if (px(BodyJoint.leftKnee) != null && px(BodyJoint.leftAnkle) != null)
        (BodyRegion.leftCalf, px(BodyJoint.leftKnee)!, px(BodyJoint.leftAnkle)!),
      if (px(BodyJoint.rightHip) != null && px(BodyJoint.rightKnee) != null)
        (
          BodyRegion.rightThigh,
          px(BodyJoint.rightHip)!,
          px(BodyJoint.rightKnee)!
        ),
      if (px(BodyJoint.rightKnee) != null && px(BodyJoint.rightAnkle) != null)
        (
          BodyRegion.rightCalf,
          px(BodyJoint.rightKnee)!,
          px(BodyJoint.rightAnkle)!
        ),
    ];

    final leftShoulder = px(BodyJoint.leftShoulder);
    final rightShoulder = px(BodyJoint.rightShoulder);
    final leftHip = px(BodyJoint.leftHip);
    final rightHip = px(BodyJoint.rightHip);

    // Torso primeiro: braços colados ao corpo não podem "roubar" a cintura —
    // isso zerava o slim no lado do braço próximo.
    if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null &&
        _isInsideTorsoQuad(
          point,
          leftShoulder,
          rightShoulder,
          rightHip,
          leftHip,
        )) {
      final shoulderY = (leftShoulder.dy + rightShoulder.dy) * 0.5;
      final hipY = (leftHip.dy + rightHip.dy) * 0.5;
      final span = math.max(hipY - shoulderY, 1.0);
      final t = ((point.dy - shoulderY) / span).clamp(0.0, 1.0);

      if (point.dy < shoulderY - span * 0.12) {
        return BodyRegion.neck;
      }
      if (t < 0.18) {
        return BodyRegion.shoulders;
      }
      if (t < 0.38) {
        return BodyRegion.chest;
      }
      if (t < 0.72) {
        return BodyRegion.waist;
      }
      if (t < 0.85) {
        return BodyRegion.hip;
      }
      if (t < 0.95) {
        return BodyRegion.butt;
      }
      return BodyRegion.torso;
    }

    final limbThreshold = math.min(imageSize.width, imageSize.height) * 0.06;
    var bestRegion = BodyRegion.torso;
    var bestDist = double.infinity;
    for (final segment in segments) {
      final dist = _distanceToSegment(point, segment.$2, segment.$3);
      if (dist < bestDist) {
        bestDist = dist;
        bestRegion = segment.$1;
      }
    }
    if (bestDist <= limbThreshold) {
      return bestRegion;
    }

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return BodyRegion.torso;
    }

    final shoulderY = (leftShoulder.dy + rightShoulder.dy) * 0.5;
    final hipY = (leftHip.dy + rightHip.dy) * 0.5;
    final span = math.max(hipY - shoulderY, 1.0);
    final t = ((point.dy - shoulderY) / span).clamp(0.0, 1.0);

    if (point.dy < shoulderY - span * 0.12) {
      return BodyRegion.neck;
    }
    if (t < 0.18) {
      return BodyRegion.shoulders;
    }
    if (t < 0.38) {
      return BodyRegion.chest;
    }
    if (t < 0.72) {
      return BodyRegion.waist;
    }
    if (t < 0.85) {
      return BodyRegion.hip;
    }
    if (t < 0.95) {
      return BodyRegion.butt;
    }
    return BodyRegion.torso;
  }

  /// Ponto dentro do quadrilátero ombroE–ombroD–quadrilD–quadrilE (com folga).
  bool _isInsideTorsoQuad(
    Offset point,
    Offset leftShoulder,
    Offset rightShoulder,
    Offset rightHip,
    Offset leftHip,
  ) {
    final midShoulderX = (leftShoulder.dx + rightShoulder.dx) * 0.5;
    final midHipX = (leftHip.dx + rightHip.dx) * 0.5;
    // Folga larga: landmarks são internos à silhueta — sem isso a borda do
    // matte cai em "braço" e o slim some num dos lados.
    final shoulderHalf =
        (rightShoulder.dx - leftShoulder.dx).abs() * 0.5 * 1.55;
    final hipHalf = (rightHip.dx - leftHip.dx).abs() * 0.5 * 1.85;
    final top = math.min(leftShoulder.dy, rightShoulder.dy) -
        (rightShoulder.dy - leftHip.dy).abs() * 0.05;
    final bottom = math.max(leftHip.dy, rightHip.dy) +
        (rightShoulder.dy - leftHip.dy).abs() * 0.08;
    if (point.dy < top || point.dy > bottom) {
      return false;
    }
    final t = ((point.dy - top) / math.max(bottom - top, 1.0)).clamp(0.0, 1.0);
    final half = shoulderHalf + (hipHalf - shoulderHalf) * t;
    final midX = midShoulderX + (midHipX - midShoulderX) * t;
    return (point.dx - midX).abs() <= half;
  }

  BodyRegion _majorityRegion(Int32List codes, int a, int b, int c) {
    final votes = <int, int>{};
    for (final index in [a, b, c]) {
      final code = codes[index];
      votes[code] = (votes[code] ?? 0) + 1;
    }
    var bestCode = BodyRegion.torso.index;
    var bestVotes = -1;
    for (final entry in votes.entries) {
      if (entry.value > bestVotes) {
        bestVotes = entry.value;
        bestCode = entry.key;
      }
    }
    if (bestCode < 0 || bestCode >= BodyRegion.values.length) {
      return BodyRegion.torso;
    }
    return BodyRegion.values[bestCode];
  }

  double _distanceToPoseSkeleton(
    Offset point,
    BodyFrameAssets assets,
    Size imageSize,
  ) {
    Offset? px(BodyJoint joint) {
      final landmark = assets.landmark(joint);
      if (landmark == null) {
        return null;
      }
      return Offset(
        landmark.normalized.dx * imageSize.width,
        landmark.normalized.dy * imageSize.height,
      );
    }

    final pairs = <(BodyJoint, BodyJoint)>[
      (BodyJoint.leftShoulder, BodyJoint.rightShoulder),
      (BodyJoint.leftShoulder, BodyJoint.leftHip),
      (BodyJoint.rightShoulder, BodyJoint.rightHip),
      (BodyJoint.leftHip, BodyJoint.rightHip),
      (BodyJoint.leftShoulder, BodyJoint.leftElbow),
      (BodyJoint.leftElbow, BodyJoint.leftWrist),
      (BodyJoint.rightShoulder, BodyJoint.rightElbow),
      (BodyJoint.rightElbow, BodyJoint.rightWrist),
      (BodyJoint.leftHip, BodyJoint.leftKnee),
      (BodyJoint.leftKnee, BodyJoint.leftAnkle),
      (BodyJoint.rightHip, BodyJoint.rightKnee),
      (BodyJoint.rightKnee, BodyJoint.rightAnkle),
    ];

    var best = double.infinity;
    for (final pair in pairs) {
      final a = px(pair.$1);
      final b = px(pair.$2);
      if (a == null || b == null) {
        continue;
      }
      best = math.min(best, _distanceToSegment(point, a, b));
    }
    return best;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-6) {
      return (p - a).distance;
    }
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0);
    final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - closest).distance;
  }
}

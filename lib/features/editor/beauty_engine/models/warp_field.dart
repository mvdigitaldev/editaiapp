import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/passes/pass_profiler.dart';
import '../body_reshape/protection/rigidity_map.dart';
import '../warp/models/control_point.dart';
import 'mesh_region.dart';
import 'tri_mesh.dart';

/// Campo de deformacao calculado pelo warp engine.
class WarpField {
  final int gridWidth;
  final int gridHeight;
  final Float32List displacement;
  final Float32List mask;
  final Size imageSize;
  final MeshRegion region;
  final List<ControlPoint> controlPoints;
  final double intensity;

  /// Rigidez estrutural do fundo aplicada (Sprint 7), se houver.
  final RigidityMap? rigidityMap;

  /// Último passe que produziu/alterou este campo (Sprint 10).
  final String? passId;

  /// Células com máscara ativa (telemetria multi-passe).
  final int? activeCellCount;

  /// Traces de profiling dos passes aplicados.
  final List<PassProfileEntry>? passProfiles;

  /// Células com jacobiano invertido antes do AntiFoldingPass.
  final int foldingCellsBefore;

  /// Células ainda invertidas após AntiFoldingPass.
  final int foldingCellsAfter;

  const WarpField({
    required this.gridWidth,
    required this.gridHeight,
    required this.displacement,
    required this.mask,
    required this.imageSize,
    required this.region,
    this.controlPoints = const [],
    this.intensity = 0,
    this.rigidityMap,
    this.passId,
    this.activeCellCount,
    this.passProfiles,
    this.foldingCellsBefore = 0,
    this.foldingCellsAfter = 0,
  });

  /// Identidade: sem intensidade, ou sem CPs e sem máscara ativa (mesh raster).
  bool get isIdentity {
    if (intensity <= 0) {
      return true;
    }
    if (controlPoints.isNotEmpty) {
      return false;
    }
    for (final value in mask) {
      if (value > 1e-6) {
        return false;
      }
    }
    return true;
  }

  WarpField reset() => WarpField.identity(imageSize: imageSize, region: region);

  WarpField copyWith({
    int? gridWidth,
    int? gridHeight,
    Float32List? displacement,
    Float32List? mask,
    Size? imageSize,
    MeshRegion? region,
    List<ControlPoint>? controlPoints,
    double? intensity,
    RigidityMap? rigidityMap,
    bool clearRigidityMap = false,
    String? passId,
    int? activeCellCount,
    List<PassProfileEntry>? passProfiles,
    int? foldingCellsBefore,
    int? foldingCellsAfter,
  }) {
    return WarpField(
      gridWidth: gridWidth ?? this.gridWidth,
      gridHeight: gridHeight ?? this.gridHeight,
      displacement: displacement ?? this.displacement,
      mask: mask ?? this.mask,
      imageSize: imageSize ?? this.imageSize,
      region: region ?? this.region,
      controlPoints: controlPoints ?? this.controlPoints,
      intensity: intensity ?? this.intensity,
      rigidityMap: clearRigidityMap ? null : (rigidityMap ?? this.rigidityMap),
      passId: passId ?? this.passId,
      activeCellCount: activeCellCount ?? this.activeCellCount,
      passProfiles: passProfiles ?? this.passProfiles,
      foldingCellsBefore: foldingCellsBefore ?? this.foldingCellsBefore,
      foldingCellsAfter: foldingCellsAfter ?? this.foldingCellsAfter,
    );
  }

  static WarpField identity({
    required Size imageSize,
    required MeshRegion region,
    int gridWidth = 8,
    int gridHeight = 8,
  }) {
    final cellCount = gridWidth * gridHeight;
    return WarpField(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      displacement: Float32List(cellCount * 2),
      mask: Float32List(cellCount),
      imageSize: imageSize,
      region: region,
      controlPoints: const [],
      intensity: 0,
    );
  }

  Offset sampleDisplacement(Offset normalized) {
    if (isIdentity) {
      return Offset.zero;
    }

    final gx = (normalized.dx * (gridWidth - 1)).clamp(0.0, gridWidth - 1.0);
    final gy = (normalized.dy * (gridHeight - 1)).clamp(0.0, gridHeight - 1.0);

    final x0 = gx.floor();
    final y0 = gy.floor();
    final x1 = (x0 + 1).clamp(0, gridWidth - 1);
    final y1 = (y0 + 1).clamp(0, gridHeight - 1);
    final tx = gx - x0;
    final ty = gy - y0;

    final d00 = _cellDisplacement(x0, y0);
    final d10 = _cellDisplacement(x1, y0);
    final d01 = _cellDisplacement(x0, y1);
    final d11 = _cellDisplacement(x1, y1);

    final dx = _lerp(_lerp(d00.dx, d10.dx, tx), _lerp(d01.dx, d11.dx, tx), ty);
    final dy = _lerp(_lerp(d00.dy, d10.dy, tx), _lerp(d01.dy, d11.dy, tx), ty);
    return Offset(dx, dy);
  }

  double sampleMask(Offset normalized) {
    if (isIdentity) {
      return 0;
    }

    final gx = (normalized.dx * (gridWidth - 1)).clamp(0.0, gridWidth - 1.0);
    final gy = (normalized.dy * (gridHeight - 1)).clamp(0.0, gridHeight - 1.0);
    final x0 = gx.floor();
    final y0 = gy.floor();
    final x1 = (x0 + 1).clamp(0, gridWidth - 1);
    final y1 = (y0 + 1).clamp(0, gridHeight - 1);
    final tx = gx - x0;
    final ty = gy - y0;

    final m00 = _cellMask(x0, y0);
    final m10 = _cellMask(x1, y0);
    final m01 = _cellMask(x0, y1);
    final m11 = _cellMask(x1, y1);

    return _lerp(_lerp(m00, m10, tx), _lerp(m01, m11, tx), ty);
  }

  Offset _cellDisplacement(int x, int y) {
    final idx = (y * gridWidth + x) * 2;
    return Offset(displacement[idx], displacement[idx + 1]);
  }

  double _cellMask(int x, int y) => mask[y * gridWidth + x];

  /// Retângulo em pixels onde a máscara é não-zero (com margem de 1 célula).
  Rect? activePixelBounds() {
    if (isIdentity) {
      return null;
    }

    var minGx = gridWidth;
    var minGy = gridHeight;
    var maxGx = -1;
    var maxGy = -1;

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        if (mask[gy * gridWidth + gx] <= 0.001) {
          continue;
        }
        if (gx < minGx) minGx = gx;
        if (gy < minGy) minGy = gy;
        if (gx > maxGx) maxGx = gx;
        if (gy > maxGy) maxGy = gy;
      }
    }

    if (maxGx < 0) {
      return null;
    }

    minGx = (minGx - 1).clamp(0, gridWidth - 1);
    minGy = (minGy - 1).clamp(0, gridHeight - 1);
    maxGx = (maxGx + 1).clamp(0, gridWidth - 1);
    maxGy = (maxGy + 1).clamp(0, gridHeight - 1);

    final left = (minGx / (gridWidth - 1)) * imageSize.width;
    final top = (minGy / (gridHeight - 1)) * imageSize.height;
    final right = (maxGx / (gridWidth - 1)) * imageSize.width;
    final bottom = (maxGy / (gridHeight - 1)) * imageSize.height;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Compõe dois warps sequenciais (aplica [first], depois [second] no resultado).
  ///
  /// Remap: `src = p + d_eff(p)`. Composição:
  /// `d_eff(p) = dB_eff(p) + dA_eff(p + dB_eff(p))`.
  static WarpField composeSequential(WarpField first, WarpField second) {
    if (first.isIdentity) return second;
    if (second.isIdentity) return first;

    final gridW = second.gridWidth;
    final gridH = second.gridHeight;
    final cellCount = gridW * gridH;
    final outDisp = Float32List(cellCount * 2);
    final outMask = Float32List(cellCount);
    final invW = second.imageSize.width > 0 ? 1.0 / second.imageSize.width : 0.0;
    final invH = second.imageSize.height > 0 ? 1.0 / second.imageSize.height : 0.0;

    for (var gy = 0; gy < gridH; gy++) {
      for (var gx = 0; gx < gridW; gx++) {
        final idx = gy * gridW + gx;
        final px = (gx / (gridW - 1)) * second.imageSize.width;
        final py = (gy / (gridH - 1)) * second.imageSize.height;
        final n = Offset(px * invW, py * invH);

        final mb = second.sampleMask(n);
        final db = second.sampleDisplacement(n);
        final mid = Offset(px + db.dx * mb, py + db.dy * mb);
        final nMid = Offset(
          (mid.dx * invW).clamp(0.0, 1.0),
          (mid.dy * invH).clamp(0.0, 1.0),
        );
        final ma = first.sampleMask(nMid);
        final da = first.sampleDisplacement(nMid);

        final effDx = db.dx * mb + da.dx * ma;
        final effDy = db.dy * mb + da.dy * ma;
        outDisp[idx * 2] = effDx;
        outDisp[idx * 2 + 1] = effDy;
        outMask[idx] = math.max(ma, mb);
      }
    }

    return WarpField(
      gridWidth: gridW,
      gridHeight: gridH,
      displacement: outDisp,
      mask: outMask,
      imageSize: second.imageSize,
      region: second.region,
      controlPoints: [...first.controlPoints, ...second.controlPoints],
      intensity: math.max(first.intensity, second.intensity),
      rigidityMap: second.rigidityMap ?? first.rigidityMap,
      passId: second.passId ?? first.passId,
      passProfiles: [
        ...?first.passProfiles,
        ...?second.passProfiles,
      ],
      foldingCellsBefore:
          first.foldingCellsBefore + second.foldingCellsBefore,
      foldingCellsAfter: second.foldingCellsAfter,
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Parametros para calculo de warp.
class WarpRequest {
  final TriMesh mesh;
  final MeshRegion region;
  final Map<String, double> parameters;
  final Size imageSize;

  const WarpRequest({
    required this.mesh,
    required this.region,
    required this.parameters,
    required this.imageSize,
  });

  double parameter(String snakeCase, {String? camelCase, double defaultValue = 0}) {
    if (parameters.containsKey(snakeCase)) {
      return parameters[snakeCase]!.clamp(0.0, 1.0);
    }
    if (camelCase != null && parameters.containsKey(camelCase)) {
      return parameters[camelCase]!.clamp(0.0, 1.0);
    }
    return defaultValue;
  }
}

import 'package:flutter/foundation.dart';

import 'face_warp_v3_rollout.dart';

/// Feature flag local do Face Warp Engine V3 (Sprint 33+).
abstract final class FaceWarpV3Config {
  static bool _defaultOn =
      kDebugMode || FaceWarpV3Rollout.preProductionForceFull;

  /// Master switch — ON em pré-produção; rollout remoto antes do release.
  static bool enabled = _defaultOn;

  /// Preferir malha+ACE em vez de MLS+grade.
  static bool useMeshWarpV3 = _defaultOn;

  /// Sprint 36 — grade densa baricêntrica (~2.5 px/célula), sem spread heurístico.
  static bool useDirectMeshRender = _defaultOn;

  /// Sprint 37 — piecewise-affine por pixel na GPU (sem grade intermediária).
  static bool useGpuPiecewiseAffine = _defaultOn;

  /// Sprint 37 — inpainting leve pós-warp para warps laterais.
  static bool usePostWarpInpaint = _defaultOn;

  /// Sprint 38 — inpaint pós-warp na GPU (preview/export).
  static bool useGpuInpaint = _defaultOn;

  /// Sprint 39 — export piecewise via Metal/GLES nativo (fallback FragmentProgram).
  static bool useNativePiecewiseExport = _defaultOn;

  /// Piecewise-affine backward na malha (face_slim preview).
  /// Malha ACE + amostragem por triângulo destino; evita splat/z-fighting.
  static bool useForwardMeshWarpFaceSlim = true;

  /// MLS facial legado (rollback lab/prod).
  static bool useLegacyFaceMls = false;

  static void toggle() {
    useMeshWarpV3 = !useMeshWarpV3;
  }

  static void toggleDirectMesh() {
    useDirectMeshRender = !useDirectMeshRender;
  }

  static void toggleGpuPiecewise() {
    useGpuPiecewiseAffine = !useGpuPiecewiseAffine;
  }

  static void togglePostWarpInpaint() {
    usePostWarpInpaint = !usePostWarpInpaint;
  }

  static void toggleGpuInpaint() {
    useGpuInpaint = !useGpuInpaint;
  }

  static void toggleNativePiecewiseExport() {
    useNativePiecewiseExport = !useNativePiecewiseExport;
  }
}

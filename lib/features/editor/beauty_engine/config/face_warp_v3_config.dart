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

  /// Caminho Extended ROI (cara+pescoço, grelha 2D) para tools de silhueta.
  /// ON em debug; off em release até validação (Sprint 7).
  static bool useExtendedRoi = kDebugMode;

  /// Telemetria `debugPrint` do ramo ROI (PassWarp / controller).
  static bool extendedRoiLog = false;

  /// Raster ROI sem hole-fill — ver warp cru (Sprint 2+).
  static bool extendedRoiSkipInpaint = false;

  /// Phase9Local na grelha ROI. Off até Sprint 6 (só log).
  static bool extendedRoiPhase9Local = false;

  /// Iterações de Newton no backward warp. Sprint 0–2: 1.
  static int extendedRoiNewtonIters = 1;

  /// Escala das amplitudes artísticas (0.5 = 50% até calibração Sprint 7).
  static double extendedRoiAmplitudeScale = 0.5;

  /// Overlay debug (ROI/grid/setas/holes).
  static bool extendedRoiDebugOverlay = false;

  /// Experimento personTransport / rigidBoundaryTest. OFF — regressão visual.
  static bool jawPersonTransportExperiment = false;

  /// `off` | `rigidBoundaryTest` (não usar).
  static String jawPersonTransportMode = 'off';

  /// JawSeamComposer experimental. OFF até auditoria de máscaras.
  static bool jawSeamComposerExperimental = false;

  /// JawBackgroundInpaint experimental. OFF até auditoria.
  static bool jawBackgroundInpaintExperimental = false;

  /// Camada JawPersonBoundary no campo. OFF até auditoria.
  static bool jawPersonBoundaryExperimental = false;

  /// Dump de PNGs intermediários do frame real. Não altera o RGBA final.
  static bool extendedRoiFrameAudit = kDebugMode;

  /// P1.1 lab: `baseline` (default, coupling 1:1) | `chinOnly` | `chinNeckLab`.
  /// O slider público usa `baseline`. Não muda o output de release.
  static String chinNeckPolicy = 'baseline';

  /// P1.3 lab: correção `curvature * 0.25` em [DenseWarpingField]. Default on.
  static bool curvatureCorrection = true;

  /// P2 lab: `A` current (default) | `B` backward-regional | `C` forward-coverage.
  /// B e C não são default de produto.
  static String roiRendererVariant = 'A';

  /// P3 lab: fill same-class da faixa released do jaw. Default off.
  /// Não muda o RGBA de release enquanto false.
  static bool semanticReleasedFill = false;

  /// P4.1: silhueta ROI pede [FacePartsDetector] (6 classes). Default on em
  /// debug. Não injecta parsing no compose/classificador e não liga o fill.
  static bool silhouetteRequestsFaceParts = kDebugMode;

  /// P4.2 lab: injecta `FacePartsSegmentation` mapped no compose/taxonomia P3.
  /// Default off — o RGBA do jaw permanece o P0. Nunca trata geometric como
  /// parsing semântico. Não liga [semanticReleasedFill].
  static bool useMappedPartsForSemanticFill = false;

  /// `face_slim` no caminho Extended ROI. Default false até A/B Sprint 5
  /// validar; migração só no Sprint 7 se ROI ganhar.
  static bool faceSlimUsesRoi = false;

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

  static void toggleExtendedRoi() {
    useExtendedRoi = !useExtendedRoi;
  }
}

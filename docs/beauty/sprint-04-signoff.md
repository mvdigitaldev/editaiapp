# Sprint 04 — Sign-off

**Sprint:** 04 — MediaPipe Pose  
**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| Bridge Android Pose | `PoseLandmarkerBridge.kt` | ✅ |
| Bridge iOS Pose | `PoseLandmarkerBridge.swift` | ✅ |
| MethodChannel `detectPose` | plugin Android + iOS + Dart | ✅ |
| Model loader pose | `ensurePoseModelOnDisk()` | ✅ |
| MediapipeInitCoordinator | init única Face + Pose | ✅ |
| PoseDetectorImpl | `pose/pose_detector_impl.dart` | ✅ |
| PoseLandmarkMapper | visibility + `isPartial` | ✅ |
| Riverpod DI | `poseDetectorProvider` | ✅ |
| Asset + script | `pose_landmarker_lite.task` | ✅ |
| Unit tests | `test/beauty_engine/pose_detector_test.dart` | ✅ |

## Critérios de aceite

- [x] Pipeline Dart: `ImageSource` → nativo → `PoseResult` (33 landmarks)
- [x] Visibility scores por landmark
- [x] `isPartial = true` quando joelhos/tornozelos < 0.5 visibility
- [x] Android build OK
- [ ] Validação em device com fotos reais — pendente

## Limitações documentadas

- Roupa larga ou pose oclusa reduz accuracy dos landmarks inferiores
- Modelo `pose_landmarker_lite` — trade-off velocidade vs precisão

## Testes

```
flutter test test/beauty_engine/   → 17/17 passando
```

## Próximo passo

**Sprint 05 — Mesh Engine**

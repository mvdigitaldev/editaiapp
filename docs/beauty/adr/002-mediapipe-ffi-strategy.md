# ADR 002 — Estratégia FFI MediaPipe (Face + Pose)

**Status:** Aprovado  
**Sprint:** 01  
**Data:** 2026-07-20

## Contexto

Beauty Engine precisa de:

- **Face Landmarker** — 478 landmarks 3D
- **Pose Landmarker** — 33 landmarks

Plataformas: **Android + iOS only**. Sem SDKs comerciais. Open source.

## Opções consideradas

| Opção | Prós | Contras |
|-------|------|---------|
| **A) FFI → MediaPipe Tasks C++** | Paridade com Meitu-level stack; iOS+Android; 478 pts | Build complexo; Gradle + CocoaPods |
| B) `google_mlkit_face_mesh_detection` | Flutter plugin pronto | Beta; **Android-only**; 468 pts |
| C) Platform Channel + Kotlin/Swift MediaPipe | Menos FFI | Duplicação Android/iOS boilerplate |
| D) TensorFlow Lite custom models | Controle total | Retreinar/manter modelos |

## Decisão

**Opção A — FFI para MediaPipe Tasks Vision**, com ordem de implementação:

1. **Sprint 03:** Android Face Landmarker
2. **Sprint 03–04:** iOS Face Landmarker
3. **Sprint 04:** Android + iOS Pose Landmarker

### Bridge nativo

```
Dart (beauty_engine/face_mesh/)
    ↕ dart:ffi + DynamicLibrary
Native plugin package: packages/beauty_mediapipe/
    ├── android/  → MediaPipe Tasks AAR + JNI
    └── ios/      → MediaPipe Tasks CocoaPods / XCFramework
```

**Pacote local:** `packages/beauty_mediapipe/` (monorepo no repo) — evita pub externo imaturo.

### API Dart unificada

```dart
// packages/beauty_mediapipe/lib/beauty_mediapipe.dart
abstract class BeautyMediapipeBindings {
  Future<void> initialize({required String faceModelPath, String? poseModelPath});
  Future<FaceLandmarkerResult?> detectFace(NativeImageBuffer buffer);
  Future<PoseLandmarkerResult?> detectPose(NativeImageBuffer buffer);
  void dispose();
}
```

Modelos `.task` em assets:

- `assets/mediapipe/face_landmarker.task`
- `assets/mediapipe/pose_landmarker.task`

(Bundled no app; ~MB cada — documentar size no Sprint 03.)

### Formato de imagem nativa

```dart
class NativeImageBuffer {
  final Uint8List bytes; // RGBA ou NV21 conforme plataforma
  final int width;
  final int height;
  final int rotation; // 0, 90, 180, 270
}
```

Conversão desde `Uint8List` JPEG export ou `image` package decode — **fora** do FFI (Dart puro).

### Fallback temporário (Sprint 03 apenas se FFI atrasar)

| Plataforma | Fallback | Limite |
|------------|----------|--------|
| Android | ML Kit Face Mesh 468 | Normalizar → 478 via interpolação; **remover** quando FFI OK |
| iOS | Nenhum — aguardar FFI | Bloqueia demo iOS face até FFI |

**Não** usar fallback em produção final.

### Threading

- Detecção roda em **platform thread** nativa (MediaPipe requirement)
- Resultado marshalled para Dart via `Isolate.run` ou callback async
- **Nunca** bloquear UI isolate > 16ms

### Tempo real (video — backlog)

- Sprint 03–04: imagem estática first
- Camera stream: Sprint 25 performance + controller `processStream`

## Build / CI

| Host | Builds |
|------|--------|
| macOS | iOS + Android (via Android SDK) |
| Linux | Android only |

CI mínimo Sprint 03: `./gradlew :beauty_mediapipe:assemble` + `flutter build apk --debug`.

## Riscos e mitigação

| Risco | Mitigação |
|-------|-----------|
| Tamanho APK +20–40MB (modelos) | Compress assets; lazy download Sprint futuro |
| MediaPipe version pin | Lock em ADR; upgrade controlado |
| iOS bitcode / arch | arm64 only |

## Critérios de aceite (Sprint 01)

- [x] FFI escolhido (MediaPipe Tasks C++)
- [x] Ordem Android → iOS documentada
- [x] Pacote `packages/beauty_mediapipe/` definido
- [x] Fallback ML Kit limitado a dev Android

## Próximos passos

Sprint 02: scaffold Dart interfaces + empty `packages/beauty_mediapipe/`  
Sprint 03: implement Android Face FFI

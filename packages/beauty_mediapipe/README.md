# beauty_mediapipe

Plugin Flutter para MediaPipe Tasks Vision (Face Landmarker + Pose Landmarker).

**Status:** Sprint 03 — Face Landmarker (Android + iOS)

## Estrutura

```
android/     → MediaPipe tasks-vision AAR + Kotlin bridge
ios/         → MediaPipeTasksVision CocoaPod + Swift bridge
lib/         → MethodChannel bindings + model loader
```

## Setup

1. Baixe o modelo no app principal:

   ```powershell
   .\scripts\download_mediapipe_models.ps1
   ```

2. O app declara `assets/mediapipe/face_landmarker.task` no `pubspec.yaml`.

## Uso

```dart
import 'package:beauty_mediapipe/beauty_mediapipe.dart';

final bindings = BeautyMediapipeMethodChannel();
final modelPath = await MediapipeModelLoader.ensureFaceModelOnDisk();
await bindings.initialize(faceModelPath: modelPath);

final result = await bindings.detectFace(
  NativeImageBuffer(bytes: jpegBytes, width: 1080, height: 1920),
);
```

Integração com Beauty Engine via `FaceMeshDetectorImpl` em `beauty_engine/face_mesh/`.

## Emulador Android

O MediaPipe **não suporta emuladores x86/x86_64**. Use:

- AVD com imagem **ARM 64** (ex.: Pixel 7 API 34, ABI `arm64-v8a`), ou
- Celular físico via USB

Se aparecer `libmediapipe_tasks_vision_jni.so not found`, troque o emulador ou use device real.

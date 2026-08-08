# Modelos MediaPipe

Baixe antes de rodar detecção no dispositivo:

```powershell
.\scripts\download_mediapipe_models.ps1
```

Modelos:
- `face_landmarker.task` — 478 landmarks faciais (Sprint 03)
- `pose_landmarker_lite.task` — 33 landmarks corporais (Sprint 04)
- `selfie_segmenter.tflite` — máscara de pessoa (Image Segmenter)
- `selfie_multiclass_256x256.tflite` — segmentação semântica em 6 classes
  (background, hair, body-skin, face-skin, clothes, others). Alimenta a
  máscara de pele do Beauty Engine; a ausência do arquivo faz a pele cair no
  fallback geométrico por landmarks, sem quebrar o editor.

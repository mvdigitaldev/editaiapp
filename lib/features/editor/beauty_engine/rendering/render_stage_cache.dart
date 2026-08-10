import 'dart:typed_data';

import '../models/face_mesh_result.dart';
import 'gpu_renderer_impl.dart';
import 'texture_handle.dart';
import '../filters/color/color_filter_pipeline.dart';

/// Cache pós-warp/pós-pele para sliders de cor a 60fps (cap. 2.4).
///
/// Quando só parâmetros de cor mudam, reutiliza a textura pré-cor e executa
/// apenas [RenderShaders.colorGrade].
class RenderStageCache {
  int? _key;
  TextureHandle? _preColorTexture;

  bool isValid(int key) => _key == key && _preColorTexture != null;

  TextureHandle? get preColorTexture => _preColorTexture;

  /// Hash estável dos parâmetros que invalidam warp/pele/LUT pós-warp.
  static int buildKey({
    required int sourceWidth,
    required int sourceHeight,
    required int sourceSampleHash,
    required Map<String, double> params,
    required String? lutAssetPath,
    FaceMeshResult? face,
    bool hasManualBrush = false,
    bool useMeshWarpV3 = false,
    bool useDirectMeshRender = false,
    bool useGpuPiecewiseAffine = false,
    bool useGpuInpaint = false,
    bool postWarpInpaintApplied = false,
  }) {
    final preColorEntries = <MapEntry<String, double>>[];
    for (final entry in params.entries) {
      if (ColorFilterPipeline.isColorKey(entry.key)) {
        continue;
      }
      preColorEntries.add(entry);
    }
    final sortedPreColor = List<MapEntry<String, double>>.of(preColorEntries)
      ..sort((a, b) => a.key.compareTo(b.key));

    var faceHash = 0;
    if (face != null) {
      final lm = face.landmarks;
      if (lm.isNotEmpty) {
        faceHash = Object.hash(
          lm.length,
          lm.first.normalized.dx,
          lm.first.normalized.dy,
          lm[lm.length ~/ 2].normalized.dx,
          lm.last.normalized.dx,
        );
      }
    }

    return Object.hash(
      sourceWidth,
      sourceHeight,
      sourceSampleHash,
      lutAssetPath,
      hasManualBrush,
      useMeshWarpV3,
      useDirectMeshRender,
      useGpuPiecewiseAffine,
      useGpuInpaint,
      postWarpInpaintApplied,
      faceHash,
      Object.hashAll(
        sortedPreColor.map((e) => Object.hash(e.key, e.value)),
      ),
    );
  }

  /// Amostra leve do buffer de origem — suficiente para detectar troca de foto.
  static int sampleRgbaHash(Uint8List rgba) {
    if (rgba.isEmpty) {
      return 0;
    }
    final mid = rgba.length ~/ 2;
    final last = rgba.length - 4;
    return Object.hash(rgba.length, rgba[0], rgba[mid], rgba[last]);
  }

  void store(GpuRendererImpl renderer, int key, TextureHandle postPreColor) {
    if (_key == key && _preColorTexture?.id == postPreColor.id) {
      return;
    }
    clear(renderer);
    _key = key;
    _preColorTexture = renderer.copyTexture(postPreColor);
  }

  void clear(GpuRendererImpl renderer) {
    final handle = _preColorTexture;
    _preColorTexture = null;
    _key = null;
    if (handle != null) {
      renderer.release(handle);
    }
  }

  void dispose(GpuRendererImpl renderer) => clear(renderer);
}

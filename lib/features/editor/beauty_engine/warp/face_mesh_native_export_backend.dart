import 'dart:typed_data';

import 'face_mesh_export_warp.dart';

/// Contrato de export piecewise nativo (Metal / GLES).
abstract class FaceMeshNativeExportBackend {
  Future<bool> get isAvailable;
  Future<void> initialize();
  Future<Uint8List?> apply(FaceMeshExportRequest request);
  void dispose();
}

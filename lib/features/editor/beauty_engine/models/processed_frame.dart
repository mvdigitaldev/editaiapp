import 'dart:typed_data';

import 'face_mesh_result.dart';
import 'pose_result.dart';

/// Frame processado pelo Beauty Engine.
class ProcessedFrame {
  final Uint8List bytes;
  final int width;
  final int height;
  final FaceMeshResult? face;
  final PoseResult? pose;

  const ProcessedFrame({
    required this.bytes,
    required this.width,
    required this.height,
    this.face,
    this.pose,
  });
}

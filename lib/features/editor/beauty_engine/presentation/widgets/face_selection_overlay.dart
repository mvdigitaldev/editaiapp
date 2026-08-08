import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../models/face_mesh_result.dart';
import '../../models/multi_face_detection.dart';
import 'preview_coordinate_mapper.dart';

/// Overlay de seleção quando há mais de um rosto na foto.
class FaceSelectionOverlay extends StatelessWidget {
  const FaceSelectionOverlay({
    super.key,
    required this.faces,
    required this.selectedIndex,
    required this.imageSize,
    required this.boxSize,
    required this.onSelected,
  });

  final List<FaceMeshResult> faces;
  final int selectedIndex;
  final Size imageSize;
  final Size boxSize;
  final ValueChanged<int> onSelected;

  static const _mapper = PreviewCoordinateMapper();

  @override
  Widget build(BuildContext context) {
    if (faces.length <= 1) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) {
        final normalized = _mapper.normalizedInImageBox(
          localPosition: details.localPosition,
          boxSize: boxSize,
        );
        if (normalized == null) {
          return;
        }
        final hit = MultiFaceDetection.indexAtNormalized(faces, normalized);
        if (hit != null && hit != selectedIndex) {
          onSelected(hit);
        }
      },
      child: CustomPaint(
        size: boxSize,
        painter: _FaceSelectionPainter(
          faces: faces,
          selectedIndex: selectedIndex,
          boxSize: boxSize,
        ),
      ),
    );
  }
}

class _FaceSelectionPainter extends CustomPainter {
  _FaceSelectionPainter({
    required this.faces,
    required this.selectedIndex,
    required this.boxSize,
  });

  final List<FaceMeshResult> faces;
  final int selectedIndex;
  final Size boxSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < faces.length; i++) {
      final box = faces[i].boundingBox;
      final rect = Rect.fromLTRB(
        box.left * boxSize.width,
        box.top * boxSize.height,
        box.right * boxSize.width,
        box.bottom * boxSize.height,
      );
      final selected = i == selectedIndex;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 2
        ..color = selected
            ? AppColors.primary
            : Colors.white.withValues(alpha: 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(8)),
        paint,
      );
      if (selected) {
        final fill = Paint()
          ..color = AppColors.primary.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(8)),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FaceSelectionPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.faces != faces;
  }
}

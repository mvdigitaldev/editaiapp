import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/face_mesh_result.dart';
import '../../warp/anatomy/anatomical_constraint_engine.dart';
import '../../warp/anatomy/anatomical_zone.dart';
import '../../warp/anatomy/face_model_specification.dart';

/// Overlay de vértices por papel anatômico (Sprint 32).
///
/// rigid = vermelho, semiRigid = amarelo, free = verde.
class AnatomyDebugOverlay extends StatelessWidget {
  const AnatomyDebugOverlay({
    super.key,
    required this.face,
    required this.imageSize,
    required this.boxSize,
    this.activeToolKey,
  });

  final FaceMeshResult face;
  final Size imageSize;
  final Size boxSize;
  final String? activeToolKey;

  @override
  Widget build(BuildContext context) {
    final spec = activeToolKey != null
        ? FaceModelSpecification.forKey(activeToolKey!)
        : null;

    return CustomPaint(
      size: boxSize,
      painter: _AnatomyDebugPainter(
        face: face,
        imageSize: imageSize,
        boxSize: boxSize,
        spec: spec,
      ),
    );
  }
}

class _AnatomyDebugPainter extends CustomPainter {
  _AnatomyDebugPainter({
    required this.face,
    required this.imageSize,
    required this.boxSize,
    required this.spec,
  });

  final FaceMeshResult face;
  final Size imageSize;
  final Size boxSize;
  final FaceToolSpecification? spec;

  @override
  void paint(Canvas canvas, Size size) {
    for (final landmark in face.landmarks) {
      if (landmark.index > 467) {
        continue;
      }
      final normalized = landmark.normalized;
      final local = Offset(
        normalized.dx * boxSize.width,
        normalized.dy * boxSize.height,
      );

      final role = AnatomicalConstraintEngine.debugRoleFor(
        landmarkIndex: landmark.index,
        spec: spec,
      );

      final color = switch (role) {
        VertexRole.rigid => const Color(0xCCFF5252),
        VertexRole.semiRigid => const Color(0xCCFFEB3B),
        VertexRole.free => const Color(0xCC69F0AE),
      };

      canvas.drawCircle(
        local,
        2.5,
        Paint()..color = color,
      );
    }

    final legend = TextPainter(
      text: TextSpan(
        text: spec != null
            ? '${spec!.parameterKey} · rigid/semi/free'
            : 'rigid · semi · free',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    legend.paint(canvas, Offset(size.width - legend.width - 8, size.height - 20));
  }

  @override
  bool shouldRepaint(covariant _AnatomyDebugPainter oldDelegate) {
    return oldDelegate.face != face ||
        oldDelegate.spec?.parameterKey != spec?.parameterKey;
  }
}

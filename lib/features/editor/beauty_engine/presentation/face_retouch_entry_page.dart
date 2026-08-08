import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/face_warp_v3_rollout_provider.dart';
import 'beauty_editor_page.dart';
import 'beauty_engine_gate.dart';

/// Rota `/face-retouch` — editor facial nativo (Beauty Engine).
class FaceRetouchEntryPage extends ConsumerWidget {
  const FaceRetouchEntryPage({super.key});

  static const _loading = Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolloutAsync = ref.watch(faceWarpV3RolloutAppliedProvider);

    return rolloutAsync.when(
      loading: () => _loading,
      error: (_, __) => const BeautyEngineGate(child: BeautyEditorPage()),
      data: (_) => const BeautyEngineGate(child: BeautyEditorPage()),
    );
  }
}

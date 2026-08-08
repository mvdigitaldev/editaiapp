import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/beauty_engine_providers.dart';
import '../../quality/parity_checklist_engine.dart';

/// Painel A/B warp B3–B6 no lab (Sprint 38).
class ParityChecklistPanel extends ConsumerWidget {
  const ParityChecklistPanel({
    super.key,
    required this.params,
  });

  final Map<String, double> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(beautyEngineControllerProvider);
    final items = ParityChecklistEngine.evaluateWarp(
      params: params,
      quality: controller.lastQualityContext,
      warpStats: controller.lastFaceWarpDebugStats,
      warpBackend: controller.lastFaceWarpBackend,
    );

    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paridade warp (B3–B6)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            for (final item in items) _Row(item: item),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});

  final ParityChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.status) {
      ParityChecklistStatus.pass => (Icons.check_circle_outline, Colors.greenAccent),
      ParityChecklistStatus.warn => (Icons.warning_amber_outlined, Colors.amberAccent),
      ParityChecklistStatus.active => (Icons.play_circle_outline, Colors.lightBlueAccent),
      ParityChecklistStatus.idle => (Icons.radio_button_unchecked, Colors.white38),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${item.id} · ${item.label}',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
          if (item.hint != null)
            Flexible(
              child: Text(
                item.hint!,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.end,
              ),
            ),
        ],
      ),
    );
  }
}

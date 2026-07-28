import 'dart:ui';

import '../models/body_frame_assets.dart';

/// Política explícita para escolher a pessoa editada quando o provider retorna
/// mais de uma instância.
///
/// Mantém a primeira versão previsível: id explícito → pessoa contendo o ponto
/// tocado → maior área → maior confiança.
class InstanceSelectionPolicy {
  const InstanceSelectionPolicy({
    this.targetInstanceId,
    this.focusPoint,
  });

  final String? targetInstanceId;
  final Offset? focusPoint;

  BodyFrameAssets? select(Iterable<BodyFrameAssets> candidates) {
    final items = candidates.toList(growable: false);
    if (items.isEmpty) {
      return null;
    }

    if (targetInstanceId != null) {
      for (final item in items) {
        if (item.instanceId == targetInstanceId) {
          return item;
        }
      }
    }

    if (focusPoint != null) {
      final touched = items
          .where((item) => item.boundingBox.contains(focusPoint!))
          .toList(growable: false);
      if (touched.isNotEmpty) {
        return _best(touched);
      }
    }
    return _best(items);
  }

  BodyFrameAssets _best(List<BodyFrameAssets> items) {
    return items.reduce((best, item) {
      final bestArea = best.boundingBox.width * best.boundingBox.height;
      final itemArea = item.boundingBox.width * item.boundingBox.height;
      if (itemArea != bestArea) {
        return itemArea > bestArea ? item : best;
      }
      return item.confidence > best.confidence ? item : best;
    });
  }
}

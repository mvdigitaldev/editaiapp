import 'package:flutter/material.dart';

import '../../../../core/theme/brand_visual.dart';
import '../l10n/beauty_engine_labels.dart';

/// Compra de filtros do marketplace, desligada até a liberação.
class PresetMarketplacePage extends StatelessWidget {
  const PresetMarketplacePage({super.key});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: const Text(BeautyEngineLabels.filterMarketplaceTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 56,
                color: BrandVisual.blue.withValues(alpha: 0.9),
              ),
              const SizedBox(height: 20),
              Text(
                BeautyEngineLabels.filterMarketplaceComingSoon,
                textAlign: TextAlign.center,
                style: BrandVisual.title(size: 20, color: onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

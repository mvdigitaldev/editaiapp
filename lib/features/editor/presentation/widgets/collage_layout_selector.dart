import 'package:flutter/material.dart';

import '../../../../core/utils/seamless_blend_curve.dart';

/// Seletor de proporção (16:9 / 4:3 / 1:1) + orientação H/V quando aplicável.
class CollageAspectSelector extends StatelessWidget {
  const CollageAspectSelector({
    super.key,
    required this.aspect,
    required this.onChanged,
  });

  final CollageAspectPreset aspect;
  final ValueChanged<CollageAspectPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<CollageAspectFamily>(
          segments: const [
            ButtonSegment(
              value: CollageAspectFamily.ratio16x9,
              label: Text('16:9'),
            ),
            ButtonSegment(
              value: CollageAspectFamily.ratio4x3,
              label: Text('4:3'),
            ),
            ButtonSegment(
              value: CollageAspectFamily.square,
              label: Text('1:1'),
            ),
          ],
          selected: {aspect.family},
          onSelectionChanged: (selection) {
            final family = selection.first;
            if (family == CollageAspectFamily.square) {
              onChanged(CollageAspectPreset.square);
              return;
            }
            onChanged(
              CollageAspectPreset(
                family: family,
                orientation: aspect.family == CollageAspectFamily.square
                    ? CollageOrientation.portrait
                    : aspect.orientation,
              ),
            );
          },
        ),
        if (aspect.family != CollageAspectFamily.square) ...[
          const SizedBox(height: 10),
          SegmentedButton<CollageOrientation>(
            segments: const [
              ButtonSegment(
                value: CollageOrientation.landscape,
                label: Text('Horizontal'),
                icon: Icon(Icons.stay_current_landscape_outlined, size: 18),
              ),
              ButtonSegment(
                value: CollageOrientation.portrait,
                label: Text('Vertical'),
                icon: Icon(Icons.stay_current_portrait_outlined, size: 18),
              ),
            ],
            selected: {aspect.orientation},
            onSelectionChanged: (selection) {
              onChanged(
                CollageAspectPreset(
                  family: aspect.family,
                  orientation: selection.first,
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

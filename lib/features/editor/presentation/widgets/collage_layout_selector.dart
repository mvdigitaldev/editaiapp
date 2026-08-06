import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/seamless_blend_curve.dart';

/// Seletor de proporção + formato do canvas + montagem (V/H).
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
              onChanged(
                aspect.copyWith(
                  family: CollageAspectFamily.square,
                  orientation: CollageOrientation.portrait,
                ),
              );
              return;
            }
            onChanged(
              aspect.copyWith(
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
            segments: [
              ButtonSegment(
                value: CollageOrientation.landscape,
                label: Text(
                  aspect.family == CollageAspectFamily.ratio16x9
                      ? '16:9'
                      : '4:3',
                ),
                icon: const Icon(Icons.stay_current_landscape_outlined, size: 18),
              ),
              ButtonSegment(
                value: CollageOrientation.portrait,
                label: Text(
                  aspect.family == CollageAspectFamily.ratio16x9
                      ? '9:16'
                      : '3:4',
                ),
                icon: const Icon(Icons.stay_current_portrait_outlined, size: 18),
              ),
            ],
            selected: {aspect.orientation},
            onSelectionChanged: (selection) {
              onChanged(aspect.copyWith(orientation: selection.first));
            },
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Montagem',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _MontageChip(
              selected:
                  aspect.stackDirection == CollageStackDirection.vertical,
              label: 'Vertical',
              onTap: () => onChanged(
                aspect.copyWith(
                  stackDirection: CollageStackDirection.vertical,
                ),
              ),
              child: const _MontageIcon(horizontal: false),
            ),
            const SizedBox(width: 10),
            _MontageChip(
              selected:
                  aspect.stackDirection == CollageStackDirection.horizontal,
              label: 'Horizontal',
              onTap: () => onChanged(
                aspect.copyWith(
                  stackDirection: CollageStackDirection.horizontal,
                ),
              ),
              child: const _MontageIcon(horizontal: true),
            ),
          ],
        ),
      ],
    );
  }
}

class _MontageChip extends StatelessWidget {
  const _MontageChip({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? AppColors.primary : AppColors.primary.withOpacity(0.25);
    final bg = selected
        ? AppColors.primary.withOpacity(0.12)
        : Colors.transparent;

    return Expanded(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
            ),
            child: Column(
              children: [
                SizedBox(width: 44, height: 44, child: child),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MontageIcon extends StatelessWidget {
  const _MontageIcon({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final fill = AppColors.primary.withOpacity(0.55);
    final gap = 3.0;

    if (horizontal) {
      return Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        SizedBox(height: gap),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}

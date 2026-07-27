import 'package:flutter/material.dart';

import '../../../../core/utils/seamless_blend_engine.dart';

class CollageLayoutSelector extends StatelessWidget {
  const CollageLayoutSelector({
    super.key,
    required this.layout,
    required this.onChanged,
  });

  final CollageLayout layout;
  final ValueChanged<CollageLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<CollageLayout>(
      segments: const [
        ButtonSegment(
          value: CollageLayout.vertical,
          label: Text('Vertical'),
          icon: Icon(Icons.view_agenda_outlined, size: 18),
        ),
        ButtonSegment(
          value: CollageLayout.horizontal,
          label: Text('Horizontal'),
          icon: Icon(Icons.view_week_outlined, size: 18),
        ),
      ],
      selected: {layout},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

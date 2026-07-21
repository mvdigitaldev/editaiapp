import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_accessible_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BeautyAccessibleSlider exposes label and value semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BeautyAccessibleSlider(
            label: 'Face Slim',
            value: 0.5,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Face Slim'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    final labelSemantics = tester.getSemantics(find.text('Face Slim'));
    expect(labelSemantics.label, 'Face Slim');
    expect(labelSemantics.value, '50%');
  });

  testWidgets('BeautyAccessibleSlider disabled when onChanged is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BeautyAccessibleSlider(
            label: 'Jaw',
            value: 0.2,
            enabled: false,
            onChanged: null,
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
  });
}

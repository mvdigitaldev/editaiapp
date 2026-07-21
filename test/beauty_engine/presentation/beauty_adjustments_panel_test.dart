import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_adjustments_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BeautyAdjustmentsPanel troca categoria e altera slider',
      (tester) async {
    final params = BeautyAdjustmentsPanel.initialParams();
    var lastKey = '';
    var lastValue = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BeautyAdjustmentsPanel(
            params: params,
            enabled: true,
            linkEyes: true,
            onParamChanged: (key, value) {
              lastKey = key;
              lastValue = value;
            },
            onLinkEyesChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Afinar rosto'), findsWidgets);

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(lastKey, 'face_slim');
    expect(lastValue, greaterThan(0));

    await tester.tap(find.text('Nariz'));
    await tester.pumpAndSettle();

    expect(find.text('Afinar nariz'), findsWidgets);
  });

  test('initialParams inclui todas as keys de warp e pele', () {
    final params = BeautyAdjustmentsPanel.initialParams();
    expect(params.containsKey('face_slim'), isTrue);
    expect(params.containsKey('nose_slim'), isTrue);
    expect(params.containsKey('waist_slim'), isTrue);
    expect(params.containsKey('skin_smooth'), isTrue);
    expect(params['link_eyes'], 1);
  });
}

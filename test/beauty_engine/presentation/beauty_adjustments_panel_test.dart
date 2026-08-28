import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_adjustments_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BeautyAdjustmentsPanel troca categoria e altera slider',
      (tester) async {
    final params = BeautyAdjustmentsPanel.initialParams();
    var lastKey = '';
    var lastValue = 0.0;

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    expect(find.text('Mandíbula'), findsWidgets);
    expect(find.text('Ângulo da mandíbula'), findsWidgets);
    expect(find.text('Tamanho do queixo'), findsWidgets);
    expect(find.text('V do queixo'), findsWidgets);
    expect(find.text('Formato V'), findsWidgets);

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(lastKey, 'jaw');
    expect(lastValue, greaterThan(0));
  });

  test('initialParams inclui jaw, chin, corpo e pele', () {
    final params = BeautyAdjustmentsPanel.initialParams();
    expect(params.containsKey('jaw'), isTrue);
    expect(params.containsKey('jaw_angle'), isTrue);
    expect(params.containsKey('jaw_angle_left'), isTrue);
    expect(params.containsKey('jaw_angle_right'), isTrue);
    expect(params.containsKey('jaw_angle_side'), isTrue);
    expect(params.containsKey('chin'), isTrue);
    expect(params.containsKey('cheekbone'), isTrue);
    expect(params.containsKey('cheekbone_left'), isTrue);
    expect(params.containsKey('cheekbone_right'), isTrue);
    expect(params.containsKey('v_chin'), isTrue);
    expect(params.containsKey('v_chin_left'), isTrue);
    expect(params.containsKey('v_chin_right'), isTrue);
    expect(params.containsKey('v_chin_side'), isTrue);
    expect(params.containsKey('v_shape'), isTrue);
    expect(params.containsKey('v_shape_left'), isTrue);
    expect(params.containsKey('v_shape_right'), isTrue);
    expect(params.containsKey('v_shape_side'), isTrue);
    expect(params.containsKey('face_slim'), isFalse);
    expect(params.containsKey('waist_slim'), isTrue);
    expect(params.containsKey('skin_smooth'), isTrue);
    expect(params['link_eyes'], 1);
  });
}

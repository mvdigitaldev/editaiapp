import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_accessible_slider.dart';
import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_adjustments_panel.dart';
import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_tool_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    Map<String, double>? params,
    void Function(String key, double value)? onParamChanged,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BeautyAdjustmentsPanel(
            params: params ?? BeautyAdjustmentsPanel.initialParams(),
            enabled: true,
            linkEyes: true,
            onParamChanged: onParamChanged ?? (_, __) {},
            onLinkEyesChanged: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('BeautyAdjustmentsPanel troca categoria e altera slider',
      (tester) async {
    var lastKey = '';
    var lastValue = 0.0;

    await pumpPanel(
      tester,
      onParamChanged: (key, value) {
        lastKey = key;
        lastValue = value;
      },
    );

    expect(find.text('Proporção'), findsWidgets);
    expect(find.text('Sobrancelha'), findsWidgets);
    expect(find.text('Linha do cabelo'), findsWidgets);
    expect(find.text('Mandíbula'), findsWidgets);
    expect(find.text('Ângulo da mandíbula'), findsWidgets);
    expect(find.text('Tamanho do queixo'), findsWidgets);
    expect(find.text('V do queixo'), findsWidgets);
    expect(find.text('Formato V'), findsWidgets);
    expect(FaceFilterPipeline.faceWarpParameterKeys.last, 'hairline');
    expect(FaceFilterPipeline.proportionParameterKeys, ['head']);
    expect(
      FaceFilterPipeline.eyebrowParameterKeys,
      ['eyebrow_height', 'eyebrow_width', 'eyebrow_end'],
    );
    expect(
      BeautyAdjustmentsPanel.categories.map((def) => def.category).toList(),
      [
        BeautyAdjustmentCategory.proporcao,
        BeautyAdjustmentCategory.rosto,
        BeautyAdjustmentCategory.sobrancelha,
        BeautyAdjustmentCategory.corpo,
        BeautyAdjustmentCategory.pele,
        BeautyAdjustmentCategory.cor,
      ],
    );

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(lastKey, 'jaw');
    expect(lastValue, greaterThan(0));
  });

  testWidgets('Rosto e Pele rendem BeautyToolIcon; Cor mantém ChoiceChip',
      (tester) async {
    await pumpPanel(tester);

    expect(
      find.byType(BeautyToolIcon),
      findsNWidgets(FaceFilterPipeline.faceWarpParameterKeys.length),
    );
    for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
      expect(find.byKey(Key('beauty-tool-icon-$key')), findsOneWidget);
    }
    final iconTops = FaceFilterPipeline.faceWarpParameterKeys
        .map((key) =>
            tester.getTopLeft(find.byKey(Key('beauty-tool-icon-$key'))).dy)
        .toSet();
    expect(iconTops.length, 1, reason: 'ícones de Rosto na mesma linha');
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.text('V do queixo'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .label,
      'V do queixo',
    );

    await tester.tap(find.text('Proporção'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beauty-tool-icon-head')), findsOneWidget);
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .label,
      'Cabeça',
    );
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .bipolar,
      isTrue,
    );

    await tester.tap(find.text('Sobrancelha'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('beauty-tool-icon-eyebrow_height')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('beauty-tool-icon-eyebrow_width')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('beauty-tool-icon-eyebrow_end')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('beauty-tool-icon-eyebrows')), findsNothing);
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .label,
      'Altura',
    );
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .bipolar,
      isTrue,
    );
    expect(find.text('Geral'), findsWidgets);

    await tester.tap(find.text('Largura'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .label,
      'Largura',
    );
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .bipolar,
      isTrue,
    );

    await tester.tap(find.text('Ponta'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .label,
      'Ponta',
    );
    expect(
      tester
          .widget<BeautyAccessibleSlider>(find.byType(BeautyAccessibleSlider))
          .bipolar,
      isTrue,
    );

    await tester.tap(find.text('Pele'));
    await tester.pumpAndSettle();
    expect(
      find.byType(BeautyToolIcon),
      findsNWidgets(SkinFilterPipeline.skinParameterKeys.length),
    );
    expect(find.text('Suavizar pele'), findsWidgets);
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.text('Cor'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.byType(BeautyToolIcon), findsNothing);
  });

  testWidgets('ponto aparece quando o valor deixa de ser zero', (tester) async {
    final params = BeautyAdjustmentsPanel.initialParams()
      ..['jaw'] = 0.4
      ..['cheekbone_left'] = 0.3;

    await pumpPanel(tester, params: params);

    expect(find.byKey(const Key('beauty-tool-dot-jaw')), findsOneWidget);
    expect(find.byKey(const Key('beauty-tool-dot-cheekbone')), findsOneWidget);
    expect(find.byKey(const Key('beauty-tool-dot-chin')), findsNothing);
  });

  testWidgets('cada glifo de Rosto e Pele pinta sem erro', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final key in BeautyToolIcons.keys)
                BeautyToolIcon(
                  toolKey: key,
                  color: Colors.black,
                ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(BeautyToolIcon),
        findsNWidgets(BeautyToolIcons.keys.length));
    expect(tester.takeException(), isNull);
  });

  test('hasGlyph cobre Rosto e Pele e ignora Cor', () {
    for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
      expect(BeautyToolIcons.hasGlyph(key), isTrue, reason: key);
    }
    for (final key in FaceFilterPipeline.proportionParameterKeys) {
      expect(BeautyToolIcons.hasGlyph(key), isTrue, reason: key);
    }
    for (final key in FaceFilterPipeline.eyebrowParameterKeys) {
      expect(BeautyToolIcons.hasGlyph(key), isTrue, reason: key);
    }
    expect(BeautyToolIcons.hasGlyph('eyebrows'), isTrue);
    for (final key in SkinFilterPipeline.skinParameterKeys) {
      expect(BeautyToolIcons.hasGlyph(key), isTrue, reason: key);
    }
    expect(BeautyToolIcons.hasGlyph('brightness'), isFalse);
    expect(BeautyToolIcons.hasGlyph('temperature'), isFalse);
  });

  test('initialParams inclui jaw, chin, corpo e pele', () {
    final params = BeautyAdjustmentsPanel.initialParams();
    expect(params.containsKey('jaw'), isTrue);
    expect(params.containsKey('jaw_angle'), isTrue);
    expect(params.containsKey('jaw_angle_left'), isTrue);
    expect(params.containsKey('jaw_angle_right'), isTrue);
    expect(params.containsKey('jaw_angle_side'), isTrue);
    expect(params.containsKey('head'), isTrue);
    expect(params.containsKey('eyebrow_height'), isTrue);
    expect(params.containsKey('eyebrow_height_left'), isTrue);
    expect(params.containsKey('eyebrow_height_right'), isTrue);
    expect(params.containsKey('eyebrow_height_side'), isTrue);
    expect(params.containsKey('eyebrow_width'), isTrue);
    expect(params.containsKey('eyebrow_width_left'), isTrue);
    expect(params.containsKey('eyebrow_width_right'), isTrue);
    expect(params.containsKey('eyebrow_width_side'), isTrue);
    expect(params.containsKey('eyebrow_end'), isTrue);
    expect(params.containsKey('eyebrow_end_left'), isTrue);
    expect(params.containsKey('eyebrow_end_right'), isTrue);
    expect(params.containsKey('eyebrow_end_side'), isTrue);
    expect(params.containsKey('hairline'), isTrue);
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

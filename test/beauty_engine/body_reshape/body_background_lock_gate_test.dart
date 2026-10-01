import 'package:editaiapp/features/editor/beauty_engine/di/body_background_lock_access_provider.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_chain.dart';
import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_accessible_slider.dart';
import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_adjustments_panel.dart';
import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/body_background_lock_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 1, 12);

  group('hasActivePaidPlan', () {
    test('free nunca tem trava', () {
      expect(
        hasActivePaidPlan(
          subscriptionTier: 'free',
          subscriptionEndsAt: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        hasActivePaidPlan(
          subscriptionTier: 'Free',
          subscriptionEndsAt: now.add(const Duration(days: 30)),
          now: now,
        ),
        isFalse,
      );
      expect(
        hasActivePaidPlan(
          subscriptionTier: null,
          subscriptionEndsAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('plano pago activo tem trava', () {
      expect(
        hasActivePaidPlan(
          subscriptionTier: 'pro',
          subscriptionEndsAt: now.add(const Duration(days: 3)),
          now: now,
        ),
        isTrue,
      );
      expect(
        hasActivePaidPlan(
          subscriptionTier: 'basic',
          subscriptionEndsAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('plano vencido não tem trava', () {
      expect(
        hasActivePaidPlan(
          subscriptionTier: 'pro',
          subscriptionEndsAt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('gatePaidFeatures', () {
    final params = {
      BodyWarpChain.waistKey: 0.6,
      BodyWarpChain.thighsKey: -0.4,
      BodyWarpChain.calvesKey: 0.5,
      BodyWarpChain.backgroundLockKey: 1.0,
    };

    test('sem direito tira a trava e mantém o slider', () {
      final gated = BodyWarpChain.gatePaidFeatures(params, allowed: false);
      expect(gated.containsKey(BodyWarpChain.backgroundLockKey), isFalse);
      expect(gated.containsKey(BodyWarpChain.thighsKey), isFalse);
      expect(gated.containsKey(BodyWarpChain.calvesKey), isFalse);
      expect(gated[BodyWarpChain.waistKey], 0.6);
      expect(BodyWarpChain.backgroundLockRequested(gated), isFalse);
      expect(params.containsKey(BodyWarpChain.backgroundLockKey), isTrue);
    });

    test('com direito fica igual', () {
      final gated = BodyWarpChain.gatePaidFeatures(params, allowed: true);
      expect(BodyWarpChain.backgroundLockRequested(gated), isTrue);
      expect(gated[BodyWarpChain.thighsKey], -0.4);
    });

    test('Coxas e Canelas são as ferramentas pagas do corpo', () {
      expect(BodyWarpChain.isPro(BodyWarpChain.thighsKey), isTrue);
      expect(BodyWarpChain.isPro(BodyWarpChain.calvesKey), isTrue);
      expect(BodyWarpChain.isPro(BodyWarpChain.legsKey), isFalse);
      expect(BodyWarpChain.isPro(BodyWarpChain.waistKey), isFalse);
      expect(
        BodyWarpChain.legParameterKeys,
        [
          BodyWarpChain.legsKey,
          BodyWarpChain.thighsKey,
          BodyWarpChain.calvesKey,
        ],
      );
    });

    test('a trava sozinha não activa a cadeia', () {
      expect(
        BodyWarpChain.hasActive({BodyWarpChain.backgroundLockKey: 1}),
        isFalse,
      );
    });
  });

  group('pílula', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool allowed,
      required bool value,
      required ValueChanged<bool> onChanged,
      required VoidCallback onLocked,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BodyBackgroundLockPill(
                value: value,
                allowed: allowed,
                enabled: true,
                onChanged: onChanged,
                onLocked: onLocked,
              ),
            ),
          ),
        ),
      );
    }

    Alignment knob(WidgetTester tester) => tester
        .widget<AnimatedAlign>(
          find.descendant(
            of: find.byKey(const ValueKey('body_bg_lock_switch')),
            matching: find.byType(AnimatedAlign),
          ),
        )
        .alignment as Alignment;

    testWidgets('é pequena e diz «Travar fundo»', (tester) async {
      await pump(
        tester,
        allowed: true,
        value: false,
        onChanged: (_) {},
        onLocked: () {},
      );
      expect(find.text('Travar fundo'), findsOneWidget);
      final size =
          tester.getSize(find.byKey(const ValueKey('body_bg_lock_pill')));
      expect(size.height, lessThanOrEqualTo(36));
    });

    testWidgets('free: não liga e abre o aviso', (tester) async {
      var locked = 0;
      final changes = <bool>[];
      await pump(
        tester,
        allowed: false,
        value: true,
        onChanged: changes.add,
        onLocked: () => locked++,
      );
      expect(knob(tester), Alignment.centerLeft);
      await tester.tap(find.byKey(const ValueKey('body_bg_lock_pill')));
      await tester.pump();
      expect(locked, 1);
      expect(changes, isEmpty);
    });

    testWidgets('pago: o toque liga e desliga', (tester) async {
      final changes = <bool>[];
      await pump(
        tester,
        allowed: true,
        value: false,
        onChanged: changes.add,
        onLocked: () => fail('não devia abrir o aviso'),
      );
      await tester.tap(find.byKey(const ValueKey('body_bg_lock_pill')));
      await tester.pump();
      expect(changes, [true]);

      await pump(
        tester,
        allowed: true,
        value: true,
        onChanged: changes.add,
        onLocked: () {},
      );
      await tester.pumpAndSettle();
      expect(knob(tester), Alignment.centerRight);
      await tester.tap(find.byKey(const ValueKey('body_bg_lock_pill')));
      await tester.pump();
      expect(changes, [true, false]);
    });
  });

  group('Coxas no painel', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool allowed,
      required ValueChanged<String> onLocked,
      Set<String> unavailable = const {},
      ValueChanged<String>? onUnavailable,
    }) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BeautyAdjustmentsPanel(
              params: BeautyAdjustmentsPanel.initialParams(),
              enabled: true,
              linkEyes: true,
              bodyOnly: true,
              proToolsAllowed: allowed,
              onProToolLocked: onLocked,
              unavailableToolKeys: unavailable,
              onUnavailableTool: onUnavailable,
              onParamChanged: (_, __) {},
              onLinkEyesChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pernas'));
      await tester.pumpAndSettle();
    }

    String sliderLabel(WidgetTester tester) => tester
        .widget<BeautyAccessibleSlider>(
          find.byType(BeautyAccessibleSlider),
        )
        .label;

    testWidgets('pernas não reconhecidas: chip cinzento, o toque só avisa',
        (tester) async {
      final notices = <String>[];
      await pump(
        tester,
        allowed: true,
        onLocked: (_) {},
        unavailable: {'legs'},
        onUnavailable: notices.add,
      );
      expect(
          find.byKey(const ValueKey('tool_unavailable_legs')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('tool_unavailable_thighs')), findsNothing);
      // O slider abre na primeira ferramenta que dá para usar.
      expect(sliderLabel(tester), 'Coxas');
      await tester.tap(find.byKey(const ValueKey('tool_chip_legs')));
      await tester.pumpAndSettle();
      expect(notices, ['legs']);
      expect(sliderLabel(tester), 'Coxas');
    });

    testWidgets('o chip das Coxas leva o cadeado rosa', (tester) async {
      await pump(tester, allowed: true, onLocked: (_) {});
      expect(find.text('Coxas'), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.byKey(const ValueKey('tool_chip_thighs')),
                matching: find.byType(Stack),
              )
              .first,
          matching: find.byKey(const ValueKey('pro_lock_badge')),
        ),
        findsOneWidget,
      );
      // Coxas e Canelas.
      expect(find.byKey(const ValueKey('pro_lock_badge')), findsNWidgets(2));
    });

    testWidgets('free: tocar nas Coxas abre o aviso e não muda de ferramenta',
        (tester) async {
      final locked = <String>[];
      await pump(tester, allowed: false, onLocked: locked.add);
      expect(sliderLabel(tester), 'Pernas');
      await tester.tap(find.byKey(const ValueKey('tool_chip_thighs')));
      await tester.pumpAndSettle();
      expect(locked, [BodyWarpChain.thighsKey]);
      expect(sliderLabel(tester), 'Pernas');
    });

    testWidgets('pago: tocar nas Coxas abre o slider das Coxas',
        (tester) async {
      await pump(
        tester,
        allowed: true,
        onLocked: (_) => fail('não devia abrir o aviso'),
      );
      await tester.tap(find.byKey(const ValueKey('tool_chip_thighs')));
      await tester.pumpAndSettle();
      expect(sliderLabel(tester), 'Coxas');
    });
  });
}

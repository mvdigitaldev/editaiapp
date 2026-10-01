import 'package:editaiapp/features/editor/beauty_engine/di/body_background_lock_access_provider.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_chain.dart';
import 'package:editaiapp/features/editor/beauty_engine/presentation/widgets/beauty_adjustments_panel.dart';
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

  group('gateBackgroundLock', () {
    final params = {
      BodyWarpChain.waistKey: 0.6,
      BodyWarpChain.backgroundLockKey: 1.0,
    };

    test('sem direito tira a trava e mantém o slider', () {
      final gated = BodyWarpChain.gateBackgroundLock(params, allowed: false);
      expect(gated.containsKey(BodyWarpChain.backgroundLockKey), isFalse);
      expect(gated[BodyWarpChain.waistKey], 0.6);
      expect(BodyWarpChain.backgroundLockRequested(gated), isFalse);
      expect(params.containsKey(BodyWarpChain.backgroundLockKey), isTrue);
    });

    test('com direito fica igual', () {
      final gated = BodyWarpChain.gateBackgroundLock(params, allowed: true);
      expect(BodyWarpChain.backgroundLockRequested(gated), isTrue);
    });

    test('a trava sozinha não activa a cadeia', () {
      expect(
        BodyWarpChain.hasActive({BodyWarpChain.backgroundLockKey: 1}),
        isFalse,
      );
    });
  });

  group('painel', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool allowed,
      required void Function(String, double) onChanged,
      required VoidCallback onLocked,
      Map<String, double>? params,
    }) async {
      tester.view.physicalSize = const Size(1200, 900);
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
              bodyOnly: true,
              backgroundLockAllowed: allowed,
              onParamChanged: onChanged,
              onLinkEyesChanged: (_) {},
              onBackgroundLockLocked: onLocked,
            ),
          ),
        ),
      );
    }

    testWidgets('free: o switch não liga e abre o aviso', (tester) async {
      var locked = 0;
      final changes = <String>[];
      await pump(
        tester,
        allowed: false,
        onChanged: (k, _) => changes.add(k),
        onLocked: () => locked++,
      );
      expect(find.text('Travar fundo'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('body_bg_lock_switch')));
      await tester.pump();
      expect(locked, 1);
      expect(changes, isEmpty);
      final sw = tester.widget<Switch>(
        find.byKey(const ValueKey('body_bg_lock_switch')),
      );
      expect(sw.value, isFalse);
    });

    testWidgets('free com a chave ligada vê o switch desligado',
        (tester) async {
      await pump(
        tester,
        allowed: false,
        onChanged: (_, __) {},
        onLocked: () {},
        params: {
          ...BeautyAdjustmentsPanel.initialParams(),
          BodyWarpChain.backgroundLockKey: 1,
        },
      );
      final sw = tester.widget<Switch>(
        find.byKey(const ValueKey('body_bg_lock_switch')),
      );
      expect(sw.value, isFalse);
    });

    testWidgets('pago: o switch grava a chave', (tester) async {
      String? key;
      double? value;
      await pump(
        tester,
        allowed: true,
        onChanged: (k, v) {
          key = k;
          value = v;
        },
        onLocked: () => fail('não devia abrir o aviso'),
      );
      await tester.tap(find.byKey(const ValueKey('body_bg_lock_switch')));
      await tester.pump();
      expect(key, BodyWarpChain.backgroundLockKey);
      expect(value, 1);
    });
  });
}

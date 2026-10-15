import 'package:editaiapp/features/auth/presentation/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Entrar fica visível sem rolagem num celular baixo',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump();

    expect(find.text('Um novo olhar para suas fotos.'), findsOneWidget);
    final entrar = find.text('Entrar');
    expect(entrar, findsOneWidget);

    final bottom = tester.getTopLeft(entrar).dy + tester.getSize(entrar).height;
    expect(bottom, lessThanOrEqualTo(667));
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:editaiapp/features/auth/presentation/pages/register_page.dart';

void main() {
  testWidgets('register page opens privacy policy document', (tester) async {
    String? openedSlug;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: const RegisterPage(),
          onGenerateRoute: (settings) {
            if (settings.name == '/legal-document') {
              openedSlug = settings.arguments as String?;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Text('Documento legal'),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );

    final privacyButton = find.text('Política de Privacidade');
    await tester.ensureVisible(privacyButton);
    await tester.tap(privacyButton);
    await tester.pumpAndSettle();

    expect(openedSlug, 'privacy-policy');
    expect(find.text('Documento legal'), findsOneWidget);
  });

  testWidgets('register page opens terms of use document', (tester) async {
    String? openedSlug;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: const RegisterPage(),
          onGenerateRoute: (settings) {
            if (settings.name == '/legal-document') {
              openedSlug = settings.arguments as String?;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Text('Documento legal'),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );

    final termsButton = find.text('Termos de Uso');
    await tester.ensureVisible(termsButton);
    await tester.tap(termsButton);
    await tester.pumpAndSettle();

    expect(openedSlug, 'terms-of-use');
    expect(find.text('Documento legal'), findsOneWidget);
  });
}

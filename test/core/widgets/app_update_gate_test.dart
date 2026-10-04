import 'package:editaiapp/core/widgets/app_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Upgrader upgrader({String? minAppVersion, required String storeVersion}) {
    return Upgrader(
      messages: UpgraderMessages(code: 'pt'),
      countryCode: 'BR',
      durationUntilAlertAgain: const Duration(days: 3),
      minAppVersion: minAppVersion,
      upgraderOS: MockUpgraderOS(android: true),
      storeController: UpgraderStoreController(
        onAndroid: () => _FixedStore(storeVersion),
      ),
    )..installPackageInfo(
        packageInfo: PackageInfo(
          appName: 'EditAI',
          packageName: 'com.editai.app',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );
  }

  Future<void> pumpGate(WidgetTester tester, Upgrader upgrader) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdateGate(
          upgrader: upgrader,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    // A loja responde num futuro e o diálogo é marcado com
    // Future.delayed(Duration.zero). Pumps com duração esgotam os dois.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('aviso opcional em português, sem Ignorar', (tester) async {
    await pumpGate(tester, upgrader(storeVersion: '2.0.0'));

    expect(find.text('Atualizar aplicação?'), findsOneWidget);
    expect(find.text('ATUALIZAR'), findsOneWidget);
    expect(find.text('MAIS TARDE'), findsOneWidget);
    expect(find.text('IGNORAR'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('abaixo da versão mínima o aviso não tem Depois', (tester) async {
    await pumpGate(
      tester,
      upgrader(storeVersion: '2.0.0', minAppVersion: '2.0.0'),
    );

    expect(find.text('ATUALIZAR'), findsOneWidget);
    expect(find.text('MAIS TARDE'), findsNothing);
    expect(find.text('IGNORAR'), findsNothing);
  });
}

class _FixedStore extends UpgraderStore {
  _FixedStore(this.storeVersion);

  final String storeVersion;

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required Version installedVersion,
    required String? country,
    required String? language,
  }) async {
    return UpgraderVersionInfo(
      appStoreListingURL: 'https://example.test',
      appStoreVersion: Version.parse(storeVersion),
      installedVersion: installedVersion,
    );
  }
}

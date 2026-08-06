import 'package:editaiapp/core/providers/app_remote_config_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomeModuleConfig', () {
    test('mantém módulos ativos quando configurações estão ausentes', () {
      final config = HomeModuleConfig.fromSettings(const {});

      expect(config.manualEdit, isTrue);
      expect(config.aiEdit, isTrue);
      expect(config.textToImage, isTrue);
      expect(config.multiImage, isTrue);
      expect(config.removeBackground, isTrue);
      expect(config.faceLab, isTrue);
    });

    test('oculta somente módulos explicitamente desativados', () {
      final config = HomeModuleConfig.fromSettings(const {
        moduleManualEditEnabledKey: 'false',
        moduleAiEditEnabledKey: 'false',
        moduleTextToImageEnabledKey: 'disable',
        moduleMultiImageEnabledKey: '0',
        moduleRemoveBackgroundEnabledKey: 'off',
        moduleFaceLabEnabledKey: 'false',
      });

      expect(config.manualEdit, isFalse);
      expect(config.aiEdit, isFalse);
      expect(config.textToImage, isFalse);
      expect(config.multiImage, isFalse);
      expect(config.removeBackground, isFalse);
      expect(config.faceLab, isFalse);
    });

    test('aceita true e enable', () {
      final config = HomeModuleConfig.fromSettings(const {
        moduleAiEditEnabledKey: 'true',
        moduleTextToImageEnabledKey: 'enable',
      });

      expect(config.aiEdit, isTrue);
      expect(config.textToImage, isTrue);
    });
  });
}


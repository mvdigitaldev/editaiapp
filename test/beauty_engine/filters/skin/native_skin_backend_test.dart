import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/native_skin_backend.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/skin_retouch_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FakeNativeSkinBackend', () {
    test('é chamado pelo contrato e devolve RGBA', () async {
      final backend = FakeNativeSkinBackend();
      final caps = await backend.probe();
      expect(caps.skinRetouch, isTrue);
      expect(caps.skinGpu, isTrue);

      final rgba = Uint8List.fromList([10, 20, 30, 255, 40, 50, 60, 255]);
      final out = await backend.skinRetouch(
        SkinRetouchRequest(
          rgba: rgba,
          width: 2,
          height: 1,
          skinWeights: Uint8List.fromList([255, 255]),
          underEyeWeights: Uint8List(2),
          params: const SkinRetouchParams(smooth: 0.5),
          faceEdgePx: 100,
        ),
      );
      expect(backend.callCount, 1);
      expect(out, rgba);
    });

    test('handler customizado pode processar', () async {
      final backend = FakeNativeSkinBackend(
        handler: (request) async {
          final out = Uint8List.fromList(request.rgba);
          out[0] = 99;
          return out;
        },
      );
      final out = await backend.skinRetouch(
        SkinRetouchRequest(
          rgba: Uint8List.fromList([1, 2, 3, 255]),
          width: 1,
          height: 1,
          skinWeights: Uint8List.fromList([255]),
          underEyeWeights: Uint8List(1),
          params: const SkinRetouchParams(smooth: 1),
          faceEdgePx: 50,
        ),
      );
      expect(out![0], 99);
    });
  });
}

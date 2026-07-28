import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/body_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/skin_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tune_params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BeautyPreset JSON', () {
    test('round-trip serializes all nested params', () {
      const original = BeautyPreset(
        id: 'natural',
        name: 'Natural',
        lutAssetPath: 'assets/filters/lut/natural.png',
        tune: TuneParams(brightness: 0.1, contrast: 0.2),
        face: FaceParams(faceSlim: 0.15),
        body: BodyParams(waistSlim: 0.05),
        skin: SkinParams(smooth: 0.3, whitening: 0.1),
        version: 2,
      );

      final decoded = BeautyPreset.fromJson(original.toJson());

      expect(decoded.id, original.id);
      expect(decoded.name, original.name);
      expect(decoded.lutAssetPath, original.lutAssetPath);
      expect(decoded.version, 2);
      expect(decoded.tune.brightness, 0.1);
      expect(decoded.tune.contrast, 0.2);
      expect(decoded.face.faceSlim, 0.15);
      expect(decoded.body.waistSlim, 0.05);
      expect(decoded.body.chestExpand, 0);
      expect(decoded.body.bellyReduce, 0);
      expect(decoded.skin.smooth, 0.3);
      expect(decoded.skin.whitening, 0.1);
    });

    test('legacy body JSON without Sprint 12 fields remains valid', () {
      final decoded = BeautyPreset.fromJson({
        'id': 'legacy',
        'name': 'Legacy',
        'version': 1,
        'body': {'waistSlim': 0.4, 'hip': 0.2},
        'face': <String, dynamic>{},
        'skin': <String, dynamic>{},
        'tune': <String, dynamic>{},
      });

      expect(decoded.version, 1);
      expect(decoded.body.waistSlim, 0.4);
      expect(decoded.body.hip, 0.2);
      expect(decoded.body.chestExpand, 0);
      expect(decoded.body.height, 0);
      expect(decoded.body.armUpperSlim, 0);
      expect(decoded.toParameterMap()['chest_expand'], 0);
      expect(decoded.toParameterMap()['waist_slim'], 0.4);
    });

    test('toParameterMap flattens nested values', () {
      const preset = BeautyPreset(
        id: 'beauty',
        name: 'Beauty',
        face: FaceParams(faceSlim: 0.5),
        skin: SkinParams(smooth: 0.25),
      );

      final map = preset.toParameterMap();

      expect(map['face_slim'], 0.5);
      expect(map['skin_smooth'], 0.25);
      expect(map['brightness'], 0);
    });
  });
}

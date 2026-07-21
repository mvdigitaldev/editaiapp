import 'package:editaiapp/features/editor/beauty_engine/config/beauty_engine_rollout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BeautyEngineRollout', () {
    test('parseMasterEnabled accepts enable only', () {
      expect(BeautyEngineRollout.parseMasterEnabled('enable'), isTrue);
      expect(BeautyEngineRollout.parseMasterEnabled('ENABLE'), isTrue);
      expect(BeautyEngineRollout.parseMasterEnabled('disable'), isFalse);
      expect(BeautyEngineRollout.parseMasterEnabled(null), isFalse);
    });

    test('parseRolloutPercent clamps 0-100', () {
      expect(BeautyEngineRollout.parseRolloutPercent('10'), 10);
      expect(BeautyEngineRollout.parseRolloutPercent('150'), 100);
      expect(BeautyEngineRollout.parseRolloutPercent('-5'), 0);
      expect(BeautyEngineRollout.parseRolloutPercent('abc'), 0);
    });

    test('stableBucket is deterministic', () {
      expect(
        BeautyEngineRollout.stableBucket('user-abc'),
        BeautyEngineRollout.stableBucket('user-abc'),
      );
    });

    test('rollout 10% includes roughly 10% of subjects', () {
      var included = 0;
      for (var i = 0; i < 1000; i++) {
        if (BeautyEngineRollout.isSubjectEnabled(
          masterEnabled: true,
          rolloutPercent: 10,
          subjectId: 'subject-$i',
        )) {
          included++;
        }
      }
      expect(included, inInclusiveRange(50, 150));
    });

    test('master disabled blocks everyone', () {
      expect(
        BeautyEngineRollout.isSubjectEnabled(
          masterEnabled: false,
          rolloutPercent: 100,
          subjectId: 'any',
        ),
        isFalse,
      );
    });

    test('100% rollout includes everyone', () {
      expect(
        BeautyEngineRollout.isSubjectEnabled(
          masterEnabled: true,
          rolloutPercent: 100,
          subjectId: 'any-user',
        ),
        isTrue,
      );
    });

    test('forceEnable bypasses remote config', () {
      expect(
        BeautyEngineRollout.isSubjectEnabled(
          masterEnabled: false,
          rolloutPercent: 0,
          subjectId: 'any',
          forceEnable: true,
        ),
        isTrue,
      );
    });
  });
}

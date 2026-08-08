import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_zone.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_model_specification.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VertexRoleMap', () {
    test('all zone landmarks are valid MediaPipe indices', () {
      expect(VertexRoleMap.validateAllZones(), isTrue);
      for (final zone in AnatomicalZone.values) {
        final landmarks = VertexRoleMap.landmarksFor(zone);
        expect(landmarks, isNotEmpty, reason: '$zone must have landmarks');
        for (final index in landmarks) {
          expect(
            VertexRoleMap.isValidLandmarkIndex(index),
            isTrue,
            reason: '$zone landmark $index out of range',
          );
        }
      }
    });

    test('oralCavity is always rigid and matches inner mouth excluded', () {
      expect(VertexRoleMap.roleFor(AnatomicalZone.oralCavity), VertexRole.rigid);
      expect(
        VertexRoleMap.oralCavity,
        equals(FaceWarpUtils.innerMouthExcluded),
      );
    });

    test('eye zones include iris landmarks', () {
      expect(VertexRoleMap.eyeLeft, contains(468));
      expect(VertexRoleMap.eyeLeft, contains(472));
      expect(VertexRoleMap.eyeRight, contains(473));
      expect(VertexRoleMap.eyeRight, contains(477));
    });

    test('every zone has a default role', () {
      for (final zone in AnatomicalZone.values) {
        expect(VertexRoleMap.defaultRole.containsKey(zone), isTrue);
      }
    });
  });

  group('FaceModelSpecification', () {
    test('covers all 22 warp filter keys', () {
      expect(FaceModelSpecification.coversAllWarpTools(), isTrue);
      for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
        expect(
          FaceModelSpecification.forKey(key),
          isNotNull,
          reason: 'missing spec for $key',
        );
      }
    });

    test('B1-B6 invariant tools are tagged', () {
      const tagged = {'B1', 'B2', 'B3', 'B4', 'B5', 'B6'};
      final found = FaceModelSpecification.toolSpecifications.values
          .map((s) => s.invariantId)
          .whereType<String>()
          .toSet();
      for (final id in tagged) {
        expect(found, contains(id));
      }
    });

    test('every tool lists oralCavity as rigid when mouth must stay fixed', () {
      const mouthSensitive = {'jaw', 'chin', 'lip_thickness', 'mouth_width', 'smile'};
      for (final key in mouthSensitive) {
        final spec = FaceModelSpecification.forKey(key)!;
        expect(
          spec.rigidZones,
          contains(AnatomicalZone.oralCavity),
          reason: '$key must pin oralCavity',
        );
      }
    });

    test('face_slim pins eyes and nose', () {
      final spec = FaceModelSpecification.forKey('face_slim')!;
      expect(spec.rigidZones, contains(AnatomicalZone.eyeLeft));
      expect(spec.rigidZones, contains(AnatomicalZone.eyeRight));
      expect(spec.rigidZones, contains(AnatomicalZone.noseAlae));
    });
  });
}

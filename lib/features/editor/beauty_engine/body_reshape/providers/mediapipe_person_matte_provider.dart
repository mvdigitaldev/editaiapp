import '../../models/image_source.dart';
import '../../segment/person_mask.dart';
import '../models/person_matte.dart';
import 'person_matte_provider.dart';
import 'vision_capabilities.dart';

/// Adaptador MediaPipe: [PersonMaskDetector] legado → [PersonMatteProvider].
class MediaPipePersonMatteProvider implements PersonMatteProvider {
  MediaPipePersonMatteProvider({
    required PersonMaskDetector detector,
  }) : _detector = detector;

  static const providerId = 'mediapipe_selfie_segmenter';

  final PersonMaskDetector _detector;

  @override
  String get id => providerId;

  @override
  VisionCapabilities get capabilities => const VisionCapabilities(
        personMatte: true,
      );

  @override
  Future<PersonMatte?> detect(ImageSource source) async {
    final mask = await _detector.detect(source);
    if (mask == null || mask.bytes.isEmpty) {
      return null;
    }
    return PersonMatte(
      alpha: mask.bytes,
      width: mask.width,
      height: mask.height,
      providerId: id,
      confidence: 1,
    );
  }
}

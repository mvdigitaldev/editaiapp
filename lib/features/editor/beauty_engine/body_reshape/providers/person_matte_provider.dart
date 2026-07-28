import '../../models/image_source.dart';
import '../models/person_matte.dart';
import 'vision_capabilities.dart';

/// Fonte de matte de pessoa (silhueta).
abstract class PersonMatteProvider {
  String get id;

  VisionCapabilities get capabilities;

  Future<PersonMatte?> detect(ImageSource source);
}

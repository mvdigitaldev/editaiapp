import '../models/image_source.dart';
import 'person_mask.dart';

/// Stub para web/desktop/testes.
class PersonMaskDetectorStub implements PersonMaskDetector {
  const PersonMaskDetectorStub();

  @override
  Future<PersonMask?> detect(ImageSource source) async => null;
}

import '../../models/image_source.dart';
import '../models/body_frame_assets.dart';
import '../models/person_matte.dart';
import 'body_mesh_provider.dart';
import 'person_matte_provider.dart';
import 'vision_capabilities.dart';

/// Provider de teste que devolve assets pré-configurados.
class FakeBodyMeshProvider implements BodyMeshProvider {
  FakeBodyMeshProvider({
    required this.assets,
    this.id = 'fake_body_mesh',
    VisionCapabilities? capabilities,
  }) : capabilities =
            capabilities ?? assets?.capabilities ?? VisionCapabilities.none;

  final BodyFrameAssets? assets;

  @override
  final String id;

  @override
  final VisionCapabilities capabilities;

  @override
  Future<BodyFrameAssets?> detect(ImageSource source) async => assets;
}

/// Provider de teste que devolve um matte pré-configurado.
class FakePersonMatteProvider implements PersonMatteProvider {
  FakePersonMatteProvider({
    required this.matte,
    this.id = 'fake_person_matte',
    this.capabilities = const VisionCapabilities(personMatte: true),
  });

  final PersonMatte? matte;

  @override
  final String id;

  @override
  final VisionCapabilities capabilities;

  @override
  Future<PersonMatte?> detect(ImageSource source) async => matte;
}

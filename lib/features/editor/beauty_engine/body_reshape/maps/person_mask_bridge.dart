import '../../segment/person_mask.dart';
import '../models/person_matte.dart';

extension PersonMaskToMatte on PersonMask {
  /// Converte a máscara legada no matte V2.
  PersonMatte toPersonMatte({
    String providerId = 'legacy_person_mask',
    double confidence = 1,
  }) {
    return PersonMatte(
      alpha: bytes,
      width: width,
      height: height,
      providerId: providerId,
      confidence: confidence,
    );
  }
}

extension PersonMatteToMask on PersonMatte {
  /// Ponte para utilitários legados que ainda consomem [PersonMask].
  PersonMask toPersonMask() {
    return PersonMask(
      bytes: alpha,
      width: width,
      height: height,
    );
  }
}

/// Classes de face parsing compatíveis com CelebAMask-HQ / BiSeNet (19 classes).
///
/// Sprint 4: hoje a maioria vem do mapeamento multiclass MediaPipe (6) +
/// landmarks; quando o modelo BiSeNet TFLite estiver no asset, o backend nativo
/// preenche esta máscara diretamente.
enum FaceParsingClass {
  background,
  skin,
  nose,
  eyeG,
  eyeL,
  browG,
  browL,
  earR,
  earL,
  mouth,
  lipUpper,
  lipLower,
  hair,
  hat,
  earRing,
  neck,
  neckL,
  cloth,
  others;

  static FaceParsingClass fromIndex(int value) {
    if (value < 0 || value >= values.length) return FaceParsingClass.others;
    return values[value];
  }
}

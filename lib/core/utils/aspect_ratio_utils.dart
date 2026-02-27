class FluxImageSize {
  final int width;
  final int height;

  const FluxImageSize(this.width, this.height);
}

FluxImageSize getFluxSizeForAspect(String aspect) {
  switch (aspect) {
    case '1:1':
      return const FluxImageSize(1024, 1024);
    case '16:9':
      return const FluxImageSize(1024, 576);
    case '9:16':
      return const FluxImageSize(576, 1024);
    case '3:4':
      return const FluxImageSize(768, 1024);
    default:
      // Default seguro: 1:1
      return const FluxImageSize(1024, 1024);
  }
}


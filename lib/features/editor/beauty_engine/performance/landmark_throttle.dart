/// Reutiliza detecção de landmarks a cada N frames (video — Sprint 25).
class LandmarkThrottle<T> {
  LandmarkThrottle({this.detectEveryNFrames = 3});

  final int detectEveryNFrames;
  int _frameIndex = 0;
  T? _cached;

  void reset() {
    _frameIndex = 0;
    _cached = null;
  }

  Future<T?> resolve(Future<T?> Function() detect) async {
    if (detectEveryNFrames <= 1 || _frameIndex % detectEveryNFrames == 0) {
      _cached = await detect();
    }
    _frameIndex++;
    return _cached;
  }
}

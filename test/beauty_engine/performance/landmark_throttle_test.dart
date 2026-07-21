import 'package:editaiapp/features/editor/beauty_engine/performance/landmark_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LandmarkThrottle reuses detection between frames', () async {
    final throttle = LandmarkThrottle<int>(detectEveryNFrames: 3);
    var calls = 0;

    Future<int> detect() async {
      calls++;
      return calls;
    }

    expect(await throttle.resolve(detect), 1);
    expect(await throttle.resolve(detect), 1);
    expect(await throttle.resolve(detect), 1);
    expect(await throttle.resolve(detect), 2);
  });
}

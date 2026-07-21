import 'package:editaiapp/features/editor/beauty_engine/performance/beauty_profiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BeautyProfiler aggregates span durations', () {
    final profiler = BeautyProfiler();
    profiler.beginFrame();
    profiler.start('render');
    profiler.end('render');
    profiler.start('render');
    profiler.end('render');

    final snapshot = profiler.snapshot();

    expect(snapshot['render'], greaterThanOrEqualTo(0));
    expect(snapshot.totalMs, greaterThanOrEqualTo(0));
  });
}

import 'package:editaiapp/features/editor/beauty_engine/performance/shader_prewarm_service.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ShaderPrewarmService executes all registered passes', () async {
    final renderer = GpuRendererImpl();
    addTearDown(renderer.dispose);

    await const ShaderPrewarmService().prewarm(renderer);

    expect(renderer.shaderCache.registeredShaders, isNotEmpty);
  });
}

import 'dart:typed_data';

import 'gpu_texture_store.dart';
import 'texture_handle.dart';

/// Pool de texturas reutilizaveis por dimensao (reduz alocacoes).
class TexturePool {
  TexturePool({GpuTextureStore? store}) : store = store ?? GpuTextureStore();

  final GpuTextureStore store;
  final Map<String, List<TextureHandle>> _freeBySize = {};

  TextureHandle acquireFromUpload(TextureUpload upload) {
    final rgba = Uint8List.fromList(upload.bytes);
    final entry = store.create(
      rgba: rgba,
      width: upload.width,
      height: upload.height,
    );
    return store.toHandle(entry);
  }

  TextureHandle acquireCopy(TextureHandle source) {
    final entry = store.get(source.id);
    if (entry == null) {
      throw StateError('Texture ${source.id} not found');
    }
    final copy = store.create(
      rgba: Uint8List.fromList(entry.rgba),
      width: entry.width,
      height: entry.height,
    );
    return store.toHandle(copy);
  }

  void release(TextureHandle handle) {
    store.release(handle.id);
  }

  void releaseAll() {
    store.clear();
    _freeBySize.clear();
  }
}

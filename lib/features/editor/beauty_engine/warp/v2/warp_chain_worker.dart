import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../controllers/beauty_engine_controller.dart';
import '../../face_mesh/face_mesh_detector_stub.dart';
import '../../mesh/mesh_engine_stub.dart';
import '../../models/face_mesh_result.dart';
import '../../models/pose_result.dart';
import '../../pose/pose_detector_stub.dart';
import '../../rendering/gpu_renderer_impl.dart';
import '../../rendering/render_target.dart';
import '../../rendering/texture_handle.dart';
import '../../segment/person_mask.dart';
import '../../warp/warp_engine_stub.dart';

/// Cadeia facial e de corpo fora da thread da UI.
///
/// O isolate guarda os `*FieldRuntime` e o RGBA de cada etapa. O preview
/// manda outra vez só o que mudou (foto, cara, pose, máscara). Os pixels são
/// os de [BeautyEngineController.applyFaceWarpChain] e
/// [BeautyEngineController.applyBodyWarpChain].
class WarpChainWorker {
  WarpChainWorker._();

  static final WarpChainWorker instance = WarpChainWorker._();

  SendPort? _port;
  Future<void>? _starting;
  var _disabled = false;
  var _nextId = 0;
  var _sourceToken = -1;
  var _faceToken = -1;
  var _poseToken = -1;
  var _maskToken = -1;
  final Map<int, Completer<Uint8List>> _waiters = {};

  bool get isDisabled => _disabled;

  Future<Uint8List> apply({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required FaceMeshResult? face,
    required PoseResult? pose,
    required PersonMask? personMask,
    required Map<String, double> parameters,
  }) async {
    if (_disabled) {
      throw StateError('warp_chain_worker_disabled');
    }
    await _ensureStarted();
    final id = ++_nextId;
    final sourceToken = identityHashCode(sourceRgba);
    final faceToken = face == null ? 0 : identityHashCode(face);
    final poseToken = pose == null ? 0 : identityHashCode(pose);
    final maskToken = personMask == null ? 0 : identityHashCode(personMask);
    final sendSource = sourceToken != _sourceToken;
    final sendFace = faceToken != _faceToken;
    final sendPose = poseToken != _poseToken;
    final sendMask = maskToken != _maskToken;
    if (sendSource) {
      _sourceToken = sourceToken;
    }
    if (sendFace) {
      _faceToken = faceToken;
    }
    if (sendPose) {
      _poseToken = poseToken;
    }
    if (sendMask) {
      _maskToken = maskToken;
    }

    final waiter = Completer<Uint8List>();
    _waiters[id] = waiter;
    try {
      _port!.send(
        _WarpChainJob(
          id: id,
          source: sendSource ? sourceRgba : null,
          width: width,
          height: height,
          replaceFace: sendFace,
          face: sendFace ? face : null,
          replacePose: sendPose,
          pose: sendPose ? pose : null,
          replaceMask: sendMask,
          personMask: sendMask ? personMask : null,
          parameters: Map<String, double>.of(parameters),
        ),
      );
    } catch (error) {
      _waiters.remove(id);
      _sourceToken = -1;
      _faceToken = -1;
      _poseToken = -1;
      _maskToken = -1;
      rethrow;
    }
    return waiter.future;
  }

  Future<void> _ensureStarted() {
    final pending = _starting;
    if (pending != null) {
      return pending;
    }
    final incoming = ReceivePort();
    final errors = ReceivePort();
    final ready = Completer<void>();
    _starting = ready.future;
    var handshake = true;
    incoming.listen((message) {
      if (handshake) {
        handshake = false;
        _port = message as SendPort;
        if (!ready.isCompleted) {
          ready.complete();
        }
        return;
      }
      final reply = message as _WarpChainReply;
      final waiter = _waiters.remove(reply.id);
      if (waiter == null || waiter.isCompleted) {
        return;
      }
      final error = reply.error;
      if (error != null) {
        waiter.completeError(StateError(error));
        return;
      }
      waiter.complete(reply.rgba!);
    });
    errors.listen((message) {
      _disabled = true;
      final error = StateError('warp_chain_worker_failed: $message');
      if (!ready.isCompleted) {
        ready.completeError(error);
      }
      for (final waiter in _waiters.values) {
        if (!waiter.isCompleted) {
          waiter.completeError(error);
        }
      }
      _waiters.clear();
    });
    Isolate.spawn(
      _warpChainWorkerMain,
      incoming.sendPort,
      onError: errors.sendPort,
      debugName: 'warp-chain',
    ).then<void>((_) {}, onError: (Object error, StackTrace stack) {
      _disabled = true;
      if (!ready.isCompleted) {
        ready.completeError(error, stack);
      }
    });
    return ready.future;
  }
}

class _WarpChainJob {
  const _WarpChainJob({
    required this.id,
    required this.source,
    required this.width,
    required this.height,
    required this.replaceFace,
    required this.face,
    required this.replacePose,
    required this.pose,
    required this.replaceMask,
    required this.personMask,
    required this.parameters,
  });

  final int id;
  final Uint8List? source;
  final int width;
  final int height;
  final bool replaceFace;
  final FaceMeshResult? face;
  final bool replacePose;
  final PoseResult? pose;
  final bool replaceMask;
  final PersonMask? personMask;
  final Map<String, double> parameters;
}

class _WarpChainReply {
  const _WarpChainReply(this.id, this.rgba, this.error);

  final int id;
  final Uint8List? rgba;
  final String? error;
}

class _IdleGpuRenderer implements GPURenderer {
  @override
  Future<TextureHandle> upload(TextureUpload upload) {
    throw UnsupportedError('warp-worker');
  }

  @override
  Future<TextureHandle> applyPass({
    required TextureHandle input,
    required String shaderName,
    Map<String, Object> uniforms = const {},
  }) {
    throw UnsupportedError('warp-worker');
  }

  @override
  Future<TextureHandle> runPipeline({
    required TextureHandle input,
    required List<RenderPipelineStage> stages,
  }) {
    throw UnsupportedError('warp-worker');
  }

  @override
  Future<Uint8List> readPixels(TextureHandle texture) {
    throw UnsupportedError('warp-worker');
  }

  @override
  Future<Uint8List> exportJpeg(TextureHandle texture, {int quality = 90}) {
    throw UnsupportedError('warp-worker');
  }

  @override
  void release(TextureHandle texture) {}

  @override
  void dispose() {}
}

void _warpChainWorkerMain(SendPort reply) {
  final incoming = ReceivePort();
  final controller = BeautyEngineController(
    faceDetector: const FaceMeshDetectorStub(),
    poseDetector: const PoseDetectorStub(),
    meshEngine: const MeshEngineStub(),
    warpEngine: const WarpEngineStub(),
    gpuRenderer: _IdleGpuRenderer(),
  );
  Uint8List? source;
  FaceMeshResult? face;
  PoseResult? pose;
  PersonMask? personMask;
  reply.send(incoming.sendPort);
  incoming.listen((message) {
    final job = message as _WarpChainJob;
    try {
      if (job.source != null) {
        source = job.source;
      }
      if (job.replaceFace) {
        face = job.face;
      }
      if (job.replacePose) {
        pose = job.pose;
      }
      if (job.replaceMask) {
        personMask = job.personMask;
      }
      final rgba = source;
      if (rgba == null) {
        reply.send(_WarpChainReply(job.id, null, 'warp_chain_sem_foto'));
        return;
      }
      final faceRgba = controller.applyFaceWarpChain(
        sourceRgba: rgba,
        width: job.width,
        height: job.height,
        face: face,
        parameters: job.parameters,
      );
      final cheekRgba = controller.applyBodyWarpChain(
        sourceRgba: faceRgba,
        width: job.width,
        height: job.height,
        pose: pose,
        personMask: personMask,
        parameters: job.parameters,
      );
      reply.send(_WarpChainReply(job.id, cheekRgba, null));
    } catch (error) {
      reply.send(_WarpChainReply(job.id, null, '$error'));
    }
  });
}

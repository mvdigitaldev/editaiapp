import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:editaiapp/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source_rgba.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_remap_debug.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Harness isolado — gera PPMs de remap debug para foto real no simulador/device.
///
/// Uso:
/// flutter run -t test/beauty_engine/warp/remap_debug_real_photo_main.dart -d <ios>
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _HarnessApp());
}

class _HarnessApp extends StatefulWidget {
  const _HarnessApp();

  @override
  State<_HarnessApp> createState() => _HarnessAppState();
}

class _HarnessAppState extends State<_HarnessApp> {
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    const tag = 'real-man-5021469-90';
    const photoAsset =
        'test/beauty_engine/warp/fixtures/man-5021469_1280.png';

    try {
      final bytes = await rootBundle.load(photoAsset);
      final decoded = img.decodeImage(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      if (decoded == null) {
        throw StateError('photo_decode_failed');
      }

      final rgba = Uint8List(decoded.width * decoded.height * 4);
      var offset = 0;
      for (var y = 0; y < decoded.height; y++) {
        for (var x = 0; x < decoded.width; x++) {
          final pixel = decoded.getPixel(x, y);
          rgba[offset++] = pixel.r.toInt();
          rgba[offset++] = pixel.g.toInt();
          rgba[offset++] = pixel.b.toInt();
          rgba[offset++] = pixel.a.toInt();
        }
      }

      final source = ImageSourceRgba.ensureRgba(
        ImageSource(
          bytes: rgba,
          width: decoded.width,
          height: decoded.height,
        ),
      );

      final bindings = BeautyMediapipeMethodChannel();
      final coordinator = MediapipeInitCoordinator(
        bindings: bindings,
        resolveFaceModelPath: MediapipeModelLoader.ensureFaceModelOnDisk,
        resolvePoseModelPath: MediapipeModelLoader.ensurePoseModelOnDisk,
      );
      final detector = FaceMeshDetectorImpl(
        bindings: bindings,
        coordinator: coordinator,
      );

      final face = await detector.detect(source);
      if (face == null) {
        throw StateError('face_detection_failed');
      }

      final imageSize = Size(
        source.width.toDouble(),
        source.height.toDouble(),
      );
      final mesh = MeshEngineImpl().buildFaceMesh(face, imageSize);
      const engine = FaceMeshDeformationEngine();
      final vertexField = engine.composeVertexField(
        parameters: const {'face_slim': 0.9},
        context: FaceAnatomyContext(
          face: face,
          imageSize: imageSize,
          mesh: mesh,
        ),
      );
      final influence = FaceMatteRoi.buildInfluenceMap(
        face: face,
        imageSize: imageSize,
        lateralRadiusExpand: 0.07,
      );
      final payload = FaceMeshForwardPayload(
        mesh: mesh,
        vertexField: vertexField,
        influenceMap: influence,
      );

      final docsDir = await getApplicationDocumentsDirectory();
      final outputDir = docsDir.path;
      debugPrint('REMAP_DEBUG_OUTPUT_DIR=$outputDir');

      final paths = FaceWarpRemapDebug.dumpFromPayloadHarness(
        rgba: source.bytes,
        width: source.width,
        height: source.height,
        payload: payload,
        tag: tag,
        runId: 'remap-debug-$tag',
        outputDirectory: outputDir,
      );

      debugPrint('REMAP_DEBUG_OK tag=$tag');
      debugPrint('coverage=${paths?.coveragePpm}');
      debugPrint('source=${paths?.sourceCoordPpm}');
      debugPrint('displacement=${paths?.displacementPpm}');
      debugPrint('magnitude=${paths?.magnitudePpm}');
    } catch (e, st) {
      debugPrint('REMAP_DEBUG_FAIL $e');
      debugPrint('$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Remap debug harness running…')),
      ),
    );
  }
}

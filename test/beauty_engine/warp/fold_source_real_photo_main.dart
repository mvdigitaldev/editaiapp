import 'dart:typed_data';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:editaiapp/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source_rgba.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_fold_source_diagnostic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Harness Fase 7 — origem do fold no vertex field.
///
/// flutter run -t test/beauty_engine/warp/fold_source_real_photo_main.dart -d <ios>
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
        resolveSegmenterModelPath: MediapipeModelLoader.ensureSegmenterModelOnDisk,
      );
      final faceDetector = FaceMeshDetectorImpl(
        bindings: bindings,
        coordinator: coordinator,
      );
      final personDetector = PersonMaskDetectorImpl(
        bindings: bindings,
        coordinator: coordinator,
      );

      final face = await faceDetector.detect(source);
      if (face == null) {
        throw StateError('face_detection_failed');
      }
      final personMask = await personDetector.detect(source);

      final imageSize = Size(
        source.width.toDouble(),
        source.height.toDouble(),
      );
      final mesh = MeshEngineImpl().buildFaceMesh(face, imageSize);

      final docsDir = await getApplicationDocumentsDirectory();
      debugPrint('FOLD_SOURCE_OUTPUT_DIR=${docsDir.path}');

      final result = await FaceWarpFoldSourceDiagnostic.run(
        face: face,
        mesh: mesh,
        width: source.width,
        height: source.height,
        personMask: personMask,
        runId: 'fold-source-man-5021469',
        outputDirectory: docsDir.path,
      );

      if (result == null) {
        throw StateError('fold_source_diagnostic_failed');
      }

      debugPrint('FOLD_SOURCE_OK');
      debugPrint('firstFold=${result.summary['firstFoldIntensity']}');
      debugPrint('supportEffect=${result.summary['supportEffect']}');
      debugPrint('root=${result.summary['rootComponent']}');
      debugPrint('summary=${result.summaryJsonPath}');
      debugPrint('hotspots=${result.hotspotsJsonPath}');
    } catch (e, st) {
      debugPrint('FOLD_SOURCE_FAIL $e');
      debugPrint('$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Fold source diagnostic running…')),
      ),
    );
  }
}

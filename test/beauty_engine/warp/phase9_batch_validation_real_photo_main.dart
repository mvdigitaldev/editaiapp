import 'dart:convert';
import 'dart:typed_data';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:editaiapp/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source_rgba.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_phase9_batch_validation_diagnostic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Harness Fase 12 — validação Phase 9 em lote (30 fotos).
///
/// flutter run -t test/beauty_engine/warp/phase9_batch_validation_real_photo_main.dart -d <ios>
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
    try {
      final manifestBytes = await rootBundle.load(
        'test/beauty_engine/warp/fixtures/phase12/manifest.json',
      );
      final manifest =
          jsonDecode(utf8.decode(manifestBytes.buffer.asUint8List())) as Map;
      final photos = (manifest['photos'] as List).cast<Map<String, dynamic>>();

      final bindings = BeautyMediapipeMethodChannel();
      final coordinator = MediapipeInitCoordinator(
        bindings: bindings,
        resolveFaceModelPath: MediapipeModelLoader.ensureFaceModelOnDisk,
        resolvePoseModelPath: MediapipeModelLoader.ensurePoseModelOnDisk,
        resolveSegmenterModelPath:
            MediapipeModelLoader.ensureSegmenterModelOnDisk,
      );
      final faceDetector = FaceMeshDetectorImpl(
        bindings: bindings,
        coordinator: coordinator,
      );
      final personDetector = PersonMaskDetectorImpl(
        bindings: bindings,
        coordinator: coordinator,
      );
      final meshEngine = MeshEngineImpl();

      final inputs = <Phase9BatchPhotoInput>[];
      var skipped = 0;

      for (final entry in photos) {
        final id = entry['id'] as String;
        final label = entry['label'] as String;
        final asset = entry['asset'] as String;

        debugPrint('P12 loading $id $asset');

        try {
          final bytes = await rootBundle.load(asset);
          final decoded = img.decodeImage(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
          if (decoded == null) {
            throw StateError('decode_failed');
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

          final face = await faceDetector.detect(source);
          if (face == null) {
            debugPrint('P12 skip $id no_face');
            skipped++;
            continue;
          }

          final personMask = await personDetector.detect(source);
          final imageSize = Size(
            source.width.toDouble(),
            source.height.toDouble(),
          );
          final mesh = meshEngine.buildFaceMesh(face, imageSize);

          inputs.add(
            Phase9BatchPhotoInput(
              id: id,
              label: label,
              face: face,
              mesh: mesh,
              width: source.width,
              height: source.height,
              personMask: personMask,
            ),
          );
        } catch (e) {
          debugPrint('P12 skip $id $e');
          skipped++;
        }
      }

      debugPrint('P12 loaded=${inputs.length} skipped=$skipped');

      final docsDir = await getApplicationDocumentsDirectory();
      debugPrint('PHASE9_BATCH_OUTPUT_DIR=${docsDir.path}');

      final result = await FaceWarpPhase9BatchValidationDiagnostic.runBatch(
        photos: inputs,
        runId: 'phase9-batch-30-photos',
        outputDirectory: docsDir.path,
      );

      if (result == null) {
        throw StateError('phase9_batch_validation_failed');
      }

      debugPrint('PHASE9_BATCH_OK');
      debugPrint('photos=${result.summary['photoCount']}');
      debugPrint('success=${result.summary['successCount']}');
      debugPrint('recommendation=${result.summary['recommendation']}');
      debugPrint('summary=${result.summaryJsonPath}');
    } catch (e, st) {
      debugPrint('PHASE9_BATCH_FAIL $e');
      debugPrint('$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Phase 9 batch validation running…'),
        ),
      ),
    );
  }
}

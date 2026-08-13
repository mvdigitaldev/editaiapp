import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:editaiapp/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source_rgba.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Exporta landmarks MediaPipe para benchmark (5 fotos reais).
///
/// flutter run -t test/beauty_engine/warp/export_benchmark_landmarks_main.dart -d <ios>
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
    const exports = [
      (
        id: 'real-p01',
        label: 'man-5021469',
        asset: 'test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png',
        out: 'test/beauty_engine/warp/fixtures/benchmark/real/p01-man-5021469.json',
      ),
      (
        id: 'real-p05',
        label: 'young-woman',
        asset: 'test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png',
        out: 'test/beauty_engine/warp/fixtures/benchmark/real/p05-young-woman.json',
      ),
      (
        id: 'real-p06',
        label: 'senior-woman',
        asset: 'test/beauty_engine/warp/fixtures/phase12/p06-senior-woman.png',
        out: 'test/beauty_engine/warp/fixtures/benchmark/real/p06-senior-woman.json',
      ),
      (
        id: 'real-p12',
        label: 'oval-man',
        asset: 'test/beauty_engine/warp/fixtures/phase12/p12.jpg',
        out: 'test/beauty_engine/warp/fixtures/benchmark/real/p12-pexels-774909.json',
      ),
      (
        id: 'real-p21',
        label: 'square-jaw',
        asset: 'test/beauty_engine/warp/fixtures/phase12/p21.jpg',
        out: 'test/beauty_engine/warp/fixtures/benchmark/real/p21-pexels-220453.json',
      ),
    ];

    try {
      final docs = await getApplicationDocumentsDirectory();
      final exportRoot = Directory('${docs.path}/benchmark_real');
      exportRoot.createSync(recursive: true);
      debugPrint('EXPORT_OUTPUT_DIR=${exportRoot.path}');

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

      final manifestEntries = <Map<String, dynamic>>[];

      for (final e in exports) {
        debugPrint('Exporting ${e.asset}');
        final bytes = await rootBundle.load(e.asset);
        final decoded = img.decodeImage(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        if (decoded == null) {
          throw StateError('decode_failed: ${e.asset}');
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
          throw StateError('face_not_detected: ${e.asset}');
        }

        final outFile = File('${exportRoot.path}/${e.id}.json');
        outFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(face.toJson()),
        );
        manifestEntries.add({
          'id': e.id,
          'label': e.label,
          'landmarkJson': e.out,
          'width': decoded.width,
          'height': decoded.height,
        });
        debugPrint(
          'OK ${e.id} ${face.landmarks.length} landmarks ${decoded.width}x${decoded.height}',
        );
      }

      final manifestFile = File('${exportRoot.path}/manifest.json');
      manifestFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({'photos': manifestEntries}),
      );
      debugPrint('Benchmark landmark export complete → ${manifestFile.path}');
      debugPrint('Pull with: xcrun simctl get_app_container booted com.example.editaiapp data');
    } catch (e, st) {
      debugPrint('EXPORT_FAIL $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Export benchmark landmarks…')),
      ),
    );
  }
}

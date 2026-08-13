import 'dart:io';
import 'dart:typed_data';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:editaiapp/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source_rgba.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mesh_geometry_diagnostic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Harness Fase 5 — diagnóstico geométrico destination mesh @ 90%.
///
/// flutter run -t test/beauty_engine/warp/mesh_geometry_real_photo_main.dart -d <ios>
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
        personMask: personMask,
        lateralRadiusExpand: 0.07,
      );
      final payload = FaceMeshForwardPayload(
        mesh: mesh,
        vertexField: vertexField,
        influenceMap: influence,
        personMask: personMask,
      );

      final docsDir = await getApplicationDocumentsDirectory();
      debugPrint('MESH_GEO_OUTPUT_DIR=${docsDir.path}');

      // Jsonl Fase 4 (fixture) — evita dependência de re-run no simulador.
      final jsonlAsset = await rootBundle.load(
        'test/beauty_engine/warp/fixtures/debug-worst-neighbor-discontinuities.jsonl',
      );
      final jsonlPath =
          '${docsDir.path}/debug-worst-neighbor-discontinuities.jsonl';
      await File(jsonlPath).writeAsBytes(
        jsonlAsset.buffer.asUint8List(
          jsonlAsset.offsetInBytes,
          jsonlAsset.lengthInBytes,
        ),
      );

      final result = await FaceWarpMeshGeometryDiagnostic.run(
        payload: payload,
        width: source.width,
        height: source.height,
        worstNeighborsJsonlPath: jsonlPath,
        runId: 'mesh-geo-real-man-5021469-90',
        outputDirectory: docsDir.path,
      );

      if (result == null) {
        throw StateError('mesh_geometry_diagnostic_failed');
      }

      debugPrint('MESH_GEO_OK');
      debugPrint('summary=${result.summary}');
      debugPrint('overlapHotspot=${result.overlapHotspotPng}');
      debugPrint('orientation=${result.orientationPng}');
      debugPrint('coverage=${result.coverageCountPng}');
      debugPrint('json=${result.summaryJsonPath}');
    } catch (e, st) {
      debugPrint('MESH_GEO_FAIL $e');
      debugPrint('$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Mesh geometry diagnostic running…')),
      ),
    );
  }
}

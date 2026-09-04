import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/controllers/beauty_engine_controller.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/chin/chin_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/jaw_angle/jaw_angle_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/jaw_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/landmark_advection.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/v_chin/v_chin_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/v_shape/v_shape_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine_stub.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../filters/skin/mvp_benchmark_faces.dart';

/// Âncoras da crista da mandíbula, partilhadas por Jaw, Jaw Angle e V Shape.
const _jawCrest = [132, 58, 172, 136, 361, 288, 397, 365];

BeautyEngineController _controller() => BeautyEngineController(
      faceDetector: const FaceMeshDetectorStub(),
      poseDetector: const PoseDetectorStub(),
      meshEngine: const MeshEngineStub(),
      warpEngine: const WarpEngineStub(),
      gpuRenderer: GPURendererStub(),
    );

FaceLandmark _landmark(
  int index,
  double x,
  double y, {
  double z = 0,
  double visibility = 1,
}) =>
    FaceLandmark(
      index: index,
      normalized: Offset(x, y),
      z: z,
      visibility: visibility,
    );

Uint8List _pattern(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    bytes[i * 4] = (i * 7) & 0xFF;
    bytes[i * 4 + 1] = (i * 13) & 0xFF;
    bytes[i * 4 + 2] = (i * 29) & 0xFF;
    bytes[i * 4 + 3] = 0xFF;
  }
  return bytes;
}

Offset? _pixelOf(FaceMeshResult face, int id, Size size) {
  for (final lm in face.landmarks) {
    if (lm.index == id) {
      return Offset(
        lm.normalized.dx * size.width,
        lm.normalized.dy * size.height,
      );
    }
  }
  return null;
}

Offset _sampleField(DisplacementField field, Offset p) {
  final x = p.dx.clamp(0.0, (field.width - 1).toDouble());
  final y = p.dy.clamp(0.0, (field.height - 1).toDouble());
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, field.width - 1);
  final y1 = math.min(y0 + 1, field.height - 1);
  final tx = x - x0;
  final ty = y - y0;
  double at(Float32List c) {
    final top = c[y0 * field.width + x0] +
        (c[y0 * field.width + x1] - c[y0 * field.width + x0]) * tx;
    final bottom = c[y1 * field.width + x0] +
        (c[y1 * field.width + x1] - c[y1 * field.width + x0]) * tx;
    return top + (bottom - top) * ty;
  }

  return Offset(at(field.dx), at(field.dy));
}

double _minDetJ(DisplacementField f) {
  var minDet = double.infinity;
  for (var y = 0; y + 1 < f.height; y++) {
    for (var x = 0; x + 1 < f.width; x++) {
      final i = y * f.width + x;
      final dxx = f.dx[i + 1] - f.dx[i];
      final dyx = f.dy[i + 1] - f.dy[i];
      final dxy = f.dx[i + f.width] - f.dx[i];
      final dyy = f.dy[i + f.width] - f.dy[i];
      final det = (1 + dxx) * (1 + dyy) - dxy * dyx;
      if (det < minDet) {
        minDet = det;
      }
    }
  }
  return minDet.isInfinite ? 1 : minDet;
}

/// Maior segunda diferença do campo no núcleo do efeito, isto é onde o
/// deslocamento vale ao menos um quarto do pico.
///
/// Mede vinco: um `minDetJ` positivo só garante que o campo não inverte, e um
/// vértice no peso passa esse crivo e ainda assim imprime uma linha na pele. O
/// núcleo exclui a fronteira do domínio, onde a rampa arranca de zero e deixa
/// sempre um joelho que nada tem a ver com o defeito.
/// Degrau com que o campo entra no domínio: maior deslocamento num pixel que
/// tenha um vizinho parado.
///
/// Mede serrilhado. As máscaras de região são binárias e rasterizadas a pixel
/// cheio, portanto a fronteira do domínio sai em degraus de um pixel; se o
/// campo entrar nela com um passo, esse passo corre em dentes ao longo da
/// silhueta. Num limite de contraste alto, como a pele contra o cabelo, lê-se
/// como serrilhado mesmo valendo menos de um pixel.
double _entryStep(DisplacementField f) {
  var worst = 0.0;
  for (var y = 1; y + 1 < f.height; y++) {
    for (var x = 1; x + 1 < f.width; x++) {
      final i = y * f.width + x;
      final v = math.sqrt(f.dx[i] * f.dx[i] + f.dy[i] * f.dy[i]);
      if (v <= worst) {
        continue;
      }
      for (final j in [i - 1, i + 1, i - f.width, i + f.width]) {
        if (f.dx[j].abs() < 1e-9 && f.dy[j].abs() < 1e-9) {
          worst = v;
          break;
        }
      }
    }
  }
  return worst;
}

double _coreCurvature(DisplacementField f) {
  var peak = 0.0;
  for (var i = 0; i < f.pixelCount; i++) {
    peak = math.max(peak, math.max(f.dx[i].abs(), f.dy[i].abs()));
  }
  if (peak < 1e-6) {
    return 0;
  }
  final gate = 0.25 * peak;
  var worst = 0.0;
  for (var y = 1; y + 1 < f.height; y++) {
    for (var x = 1; x + 1 < f.width; x++) {
      final i = y * f.width + x;
      if (math.max(f.dx[i].abs(), f.dy[i].abs()) < gate) {
        continue;
      }
      for (final v in [f.dx, f.dy]) {
        worst = math.max(
          worst,
          math.max(
            (v[i + 1] - 2 * v[i] + v[i - 1]).abs(),
            (v[i + f.width] - 2 * v[i] + v[i - f.width]).abs(),
          ),
        );
      }
    }
  }
  return worst;
}

/// Réplica da cadeia do controller: cada campo é construído sobre os landmarks
/// que as etapas anteriores deixaram.
///
/// Com `advect: false` reproduz o arranjo anterior, em que todas as etapas
/// mediam a geometria de origem — serve de linha de base nas comparações.
List<DisplacementField> _chainFields({
  required FaceMeshResult face,
  required Size imageSize,
  double jaw = 0,
  double jawAngle = 0,
  double chin = 0,
  double vChin = 0,
  double vShape = 0,
  double cheekbone = 0,
  bool advect = true,
}) {
  final builders = <DisplacementField? Function(FaceMeshResult)>[
    (f) => jaw <= 0
        ? null
        : JawField.build(face: f, imageSize: imageSize, t: jaw).field,
    (f) => jawAngle == 0
        ? null
        : JawAngleField.build(
            face: f,
            imageSize: imageSize,
            t: jawAngle,
            computeMetrics: false,
          ).field,
    (f) => chin == 0
        ? null
        : ChinField.build(
            face: f,
            imageSize: imageSize,
            t: chin,
            computeMetrics: false,
          ).field,
    (f) => vChin == 0
        ? null
        : VChinField.build(
            face: f,
            imageSize: imageSize,
            t: vChin,
            computeMetrics: false,
          ).field,
    (f) => vShape == 0
        ? null
        : VShapeField.build(
            face: f,
            imageSize: imageSize,
            t: vShape,
            computeMetrics: false,
          ).field,
    (f) => cheekbone == 0
        ? null
        : CheekbonesField.build(
            face: f,
            imageSize: imageSize,
            t: cheekbone,
            computeMetrics: false,
          ).field,
  ];

  final fields = <DisplacementField>[];
  var current = face;
  for (final build in builders) {
    final field = build(current);
    if (field == null) {
      continue;
    }
    fields.add(field);
    if (advect) {
      current = LandmarkAdvection.advance(
        face: current,
        field: field,
        imageSize: imageSize,
      );
    }
  }
  return fields;
}

void main() {
  final faces = loadAvailableRealBenchmarkFaces().toList();

  group('LandmarkAdvection', () {
    test('reproduz uma translação uniforme', () {
      const size = Size(64, 48);
      final field = DisplacementField.translation(
        width: 64,
        height: 48,
        dx: 5,
        dy: -3,
      );
      final face = FaceMeshResult(
        landmarks: [
          for (var i = 0; i < 3; i++) _landmark(i, 0.25 + i * 0.1, 0.5),
        ],
        boundingBox: const Rect.fromLTRB(0, 0, 1, 1),
        confidence: 1,
      );

      final moved = LandmarkAdvection.advance(
        face: face,
        field: field,
        imageSize: size,
      );

      for (var i = 0; i < face.landmarks.length; i++) {
        final before = _pixelOf(face, i, size)!;
        final after = _pixelOf(moved, i, size)!;
        expect(after.dx - before.dx, closeTo(5, 1e-6));
        expect(after.dy - before.dy, closeTo(-3, 1e-6));
      }
    });

    test('preserva index, z e visibility', () {
      const size = Size(32, 32);
      final field = DisplacementField.translation(
        width: 32,
        height: 32,
        dx: 2,
        dy: 2,
      );
      final face = FaceMeshResult(
        landmarks: [_landmark(7, 0.5, 0.5, z: 0.3, visibility: 0.6)],
        boundingBox: Rect.zero,
        confidence: 0.9,
      );

      final moved = LandmarkAdvection.advance(
        face: face,
        field: field,
        imageSize: size,
      );

      expect(moved.landmarks.single.index, 7);
      expect(moved.landmarks.single.z, closeTo(0.3, 1e-9));
      expect(moved.landmarks.single.visibility, closeTo(0.6, 1e-9));
      expect(moved.confidence, closeTo(0.9, 1e-9));
    });

    test('recusa campo com tamanho diferente da imagem', () {
      final field = DisplacementField.zeros(width: 8, height: 8);
      final face = FaceMeshResult(
        landmarks: [_landmark(0, 0.5, 0.5)],
        boundingBox: Rect.zero,
        confidence: 1,
      );
      expect(
        () => LandmarkAdvection.advance(
          face: face,
          field: field,
          imageSize: const Size(16, 16),
        ),
        throwsStateError,
      );
    });
  });

  group('Cadeia facial — advecção corrige o desalinhamento', () {
    for (final sample in faces.take(3)) {
      test('resíduo é sub-pixel sob a crista — ${sample.id}', () {
        final jaw = JawField.build(
          face: sample.face,
          imageSize: sample.imageSize,
          t: 1,
        ).field;
        final advected = LandmarkAdvection.advance(
          face: sample.face,
          field: jaw,
          imageSize: sample.imageSize,
        );

        var worstBefore = 0.0;
        var worstAfter = 0.0;
        for (final id in _jawCrest) {
          final origin = _pixelOf(sample.face, id, sample.imageSize);
          final moved = _pixelOf(advected, id, sample.imageSize);
          if (origin == null || moved == null) {
            continue;
          }
          // Antes: a silhueta escorrega |D(p)| sob o landmark, que ficava parado.
          worstBefore =
              math.max(worstBefore, _sampleField(jaw, origin).distance);
          // Depois: o landmark satisfaz o remap backward `q − D(q) = p`.
          final d = _sampleField(jaw, moved);
          worstAfter = math.max(
            worstAfter,
            (moved - d - origin).distance,
          );
        }

        expect(
          worstBefore,
          greaterThan(3),
          reason: 'a fixture deixou de exercer o desalinhamento que se corrige',
        );
        expect(
          worstAfter,
          lessThan(0.5),
          reason: 'crista do efeito a jusante continua fora da silhueta',
        );
      });
    }
  });

  group('Cadeia facial — composição não dobra', () {
    for (final sample in faces.take(3)) {
      test('jaw + jaw_angle + v_shape, ambos os sinais — ${sample.id}', () {
        for (final angle in [1.0, -1.0]) {
          for (final shape in [1.0, -1.0]) {
            final fields = _chainFields(
              face: sample.face,
              imageSize: sample.imageSize,
              jaw: 1,
              jawAngle: angle,
              vShape: shape,
            );
            expect(fields.length, 3);
            for (var i = 0; i < fields.length; i++) {
              expect(
                _minDetJ(fields[i]),
                greaterThan(0),
                reason: 'etapa $i dobra com angle=$angle shape=$shape',
              );
            }
          }
        }
      });
    }

    test('seis efeitos no extremo não agravam o detJ de cada etapa', () {
      final sample = faces.first;
      for (final angle in [1.0, -1.0]) {
        for (final chin in [1.0, -1.0]) {
          for (final vChin in [1.0, -1.0]) {
            for (final vShape in [1.0, -1.0]) {
              for (final cheek in [1.0, -1.0]) {
                final chained = _chainFields(
                  face: sample.face,
                  imageSize: sample.imageSize,
                  jaw: 1,
                  jawAngle: angle,
                  chin: chin,
                  vChin: vChin,
                  vShape: vShape,
                  cheekbone: cheek,
                );
                final alone = _chainFields(
                  face: sample.face,
                  imageSize: sample.imageSize,
                  jaw: 1,
                  jawAngle: angle,
                  chin: chin,
                  vChin: vChin,
                  vShape: vShape,
                  cheekbone: cheek,
                  advect: false,
                );
                expect(chained.length, 6);
                expect(alone.length, 6);
                for (var i = 0; i < chained.length; i++) {
                  expect(
                    _minDetJ(alone[i]),
                    greaterThan(0),
                    reason: 'etapa $i dobra já isolada em '
                        'angle=$angle chin=$chin vchin=$vChin '
                        'vshape=$vShape cheek=$cheek',
                  );
                  expect(
                    _minDetJ(chained[i]),
                    greaterThan(0),
                    reason: 'a advecção introduziu dobra na etapa $i em '
                        'angle=$angle chin=$chin vchin=$vChin '
                        'vshape=$vShape cheek=$cheek',
                  );
                }
              }
            }
          }
        }
      }
    });

    for (final sample in faces) {
      test('nenhum efeito dobra isolado nos dois extremos — ${sample.id}', () {
        for (final t in [1.0, -1.0]) {
          final fields = _chainFields(
            face: sample.face,
            imageSize: sample.imageSize,
            jaw: t > 0 ? 1 : 0,
            jawAngle: t,
            chin: t,
            vChin: t,
            vShape: t,
            cheekbone: t,
            advect: false,
          );
          for (var i = 0; i < fields.length; i++) {
            expect(
              _minDetJ(fields[i]),
              greaterThan(0),
              reason: 'efeito $i dobra isolado a t=$t',
            );
          }
        }
      });
    }

    // Tectos medidos com a rampa de fronteira borrada e a crista contínua. A
    // rampa crua deixava aqui 0,49 a 0,88, e era essa linha diagonal, paralela
    // à silhueta e a meio da bochecha, que aparecia com Mandíbula e Formato V
    // no extremo.
    //
    // O `v_chin` fica de fora do tecto comum: o joelho do `midGate` continua
    // vivo e vale `amplitude / midBlend`, que com os 0,080 de amplitude deste
    // efeito é também o que lhe segura o `minDetJ`. Suavizar esse joelho pede
    // menos amplitude, o que é decisão de calibração e não desta correcção.
    const coreCeiling = <String, double>{
      'jaw': 0.25,
      'jaw_angle': 0.25,
      'chin': 0.25,
      'v_chin': 0.55,
      // O `v_shape` tem tecto próprio porque as caudas na silhueta lhe levaram
      // mais amplitude ao gónio: o campo lá passou de 1,9 a 8,0 px e a
      // curvatura subiu de 0,204 para 0,250, ou seja 23% para 4× de amplitude.
      // É o perfil a escalar, não descontinuidade.
      'v_shape': 0.30,
      'cheekbone': 0.25,
    };

    // Tectos do degrau de entrada, em pixels. Com a rampa linear o campo
    // entrava no domínio a 0,20 px no `jaw` e a 0,23 px no `v_shape`, e era
    // esse passo que serrilhava a silhueta contra o cabelo. O smoothstep e o
    // alisamento da rasterização deixaram-nos abaixo de 0,09 px.
    //
    // O `cheekbone` tem tecto próprio: quem lhe manda o campo a zero junto à
    // orelha é a rampa de 13 px do `earFalloff`, curta de mais para a zona onde
    // o efeito está no seu pico. Encurtar esse degrau pede recalibrar o
    // `earFalloff`, que é decisão do Sprint do efeito e não desta correcção.
    const entryCeiling = <String, double>{
      'jaw': 0.08,
      'jaw_angle': 0.06,
      'chin': 0.10,
      'v_chin': 0.14,
      'v_shape': 0.06,
      'cheekbone': 0.30,
    };

    // Oval do lado direito MP (esquerda da foto), de cima para baixo: têmpora,
    // lateral do rosto, gónio, curva da mandíbula, mento.
    const silhouette = [93, 132, 58, 172, 136, 150];

    for (final sample in faces) {
      test('Mandíbula e Formato V somam sem bico na silhueta — ${sample.id}',
          () {
        final size = sample.imageSize;
        final jaw = JawField.build(
          face: sample.face,
          imageSize: size,
          t: 1,
        ).field;
        final advected = LandmarkAdvection.advance(
          face: sample.face,
          field: jaw,
          imageSize: size,
        );
        final vShape = VShapeField.build(
          face: advected,
          imageSize: size,
          t: 1,
          computeMetrics: false,
        ).field;

        // Deslocamento total de cada ponto da silhueta, pelos dois remaps.
        final moved = <double>[];
        for (final id in silhouette) {
          final lm = sample.face.landmarks.firstWhere((l) => l.index == id);
          final p = Offset(
            lm.normalized.dx * size.width,
            lm.normalized.dy * size.height,
          );
          final after = LandmarkAdvection.advancePoint(
            vShape,
            LandmarkAdvection.advancePoint(jaw, p),
          );
          moved.add((after - p).distance);
        }

        // O Formato V punha um pico isolado sobre o planalto do Jaw: 23,5 px
        // no 172 contra 14 px nos vizinhos, ou seja 1,66×, que é a concavidade
        // abrupta que se via na silhueta. Com as caudas o perfil passou a
        // planalto e a razão caiu para 1,10.
        for (var i = 1; i + 1 < moved.length; i++) {
          final neighbour = math.max(moved[i - 1], moved[i + 1]);
          if (neighbour < 1) {
            continue;
          }
          expect(
            moved[i] / neighbour,
            lessThan(1.35),
            reason: 'bico no landmark ${silhouette[i]}: '
                '${moved.map((v) => v.toStringAsFixed(1)).toList()}',
          );
        }

        // E a cauda tem de existir: sem ela o efeito acaba em seco no gónio.
        expect(
          moved[1],
          greaterThan(0.35 * moved[3]),
          reason: 'cauda fraca no 132: '
              '${moved.map((v) => v.toStringAsFixed(1)).toList()}',
        );
      });
    }

    for (final sample in faces) {
      test('nenhum efeito vinca o núcleo nem entra com degrau — ${sample.id}',
          () {
        for (final t in [1.0, -1.0]) {
          final fields = <String, DisplacementField>{
            'jaw': JawField.build(
              face: sample.face,
              imageSize: sample.imageSize,
              t: t > 0 ? 1 : 0,
            ).field,
            'jaw_angle': JawAngleField.build(
              face: sample.face,
              imageSize: sample.imageSize,
              t: t,
              computeMetrics: false,
            ).field,
            'chin': ChinField.build(
              face: sample.face,
              imageSize: sample.imageSize,
              t: t,
              computeMetrics: false,
            ).field,
            'v_chin': VChinField.build(
              face: sample.face,
              imageSize: sample.imageSize,
              t: t,
              computeMetrics: false,
            ).field,
            'v_shape': VShapeField.build(
              face: sample.face,
              imageSize: sample.imageSize,
              t: t,
              computeMetrics: false,
            ).field,
            'cheekbone': CheekbonesField.build(
              face: sample.face,
              imageSize: sample.imageSize,
              t: t,
              computeMetrics: false,
            ).field,
          };
          for (final e in fields.entries) {
            expect(
              _coreCurvature(e.value),
              lessThan(coreCeiling[e.key]!),
              reason: '${e.key} vinca o núcleo a t=$t',
            );
            expect(
              _entryStep(e.value),
              lessThan(entryCeiling[e.key]!),
              reason: '${e.key} entra no domínio com degrau a t=$t',
            );
          }
        }
      });
    }
  });

  group('applyFaceWarpChain', () {
    test('eyebrow_width entra depois da altura e antes do jaw', () {
      expect(
        BeautyEngineController.faceWarpChainStages
            .map((stage) => stage.backend)
            .toList(),
        [
          'v2_head',
          'v2_hairline',
          'v2_eyebrow_height',
          'v2_eyebrow_width',
          'v2_jaw',
          'v2_jaw_angle',
          'v2_chin',
          'v2_v_chin',
          'v2_v_shape',
          'v2_cheekbone',
        ],
      );
    });

    test('é identidade com todos os sliders em zero', () {
      final sample = faces.first;
      final width = sample.imageSize.width.round();
      final height = sample.imageSize.height.round();
      final source = _pattern(width, height);

      final out = _controller().applyFaceWarpChain(
        sourceRgba: source,
        width: width,
        height: height,
        face: sample.face,
        parameters: const {},
      );

      expect(out, same(source));
    });

    test('sem face devolve os bytes de origem', () {
      final source = _pattern(8, 8);
      final out = _controller().applyFaceWarpChain(
        sourceRgba: source,
        width: 8,
        height: 8,
        face: null,
        parameters: const {'jaw': 1},
      );
      expect(out, same(source));
    });

    for (final effect in [
      ('head', -1.0),
      ('hairline', -1.0),
      ('eyebrow_height', 1.0),
      ('eyebrow_width', 1.0),
      ('jaw', 1.0),
      ('jaw_angle', -1.0),
      ('chin', 1.0),
      ('v_chin', 1.0),
      ('v_shape', 1.0),
      ('cheekbone', 1.0),
    ]) {
      test('um único efeito activo (${effect.$1}) preserva o resultado isolado',
          () {
        final sample = faces.first;
        final width = sample.imageSize.width.round();
        final height = sample.imageSize.height.round();
        final params = {effect.$1: effect.$2};
        final controller = _controller();

        final viaChain = controller.applyFaceWarpChain(
          sourceRgba: _pattern(width, height),
          width: width,
          height: height,
          face: sample.face,
          parameters: params,
        );

        final isolated = switch (effect.$1) {
          'head' => controller.applyHeadWarp,
          'hairline' => controller.applyHairlineWarp,
          'eyebrow_height' => controller.applyEyebrowHeightWarp,
          'eyebrow_width' => controller.applyEyebrowWidthWarp,
          'jaw' => controller.applyJawWarp,
          'jaw_angle' => controller.applyJawAngleWarp,
          'chin' => controller.applyChinWarp,
          'v_chin' => controller.applyVChinWarp,
          'v_shape' => controller.applyVShapeWarp,
          _ => controller.applyCheekbonesWarp,
        }(
          sourceRgba: _pattern(width, height),
          width: width,
          height: height,
          face: sample.face,
          parameters: params,
        );

        expect(viaChain, orderedEquals(isolated));
      });
    }

    test('reaproveita a advecção quando só o último slider muda', () {
      final sample = faces.first;
      final width = sample.imageSize.width.round();
      final height = sample.imageSize.height.round();
      final controller = _controller();

      Uint8List run(double cheek) => controller.applyFaceWarpChain(
            sourceRgba: _pattern(width, height),
            width: width,
            height: height,
            face: sample.face,
            parameters: {'jaw': 1, 'cheekbone': cheek},
          );

      final first = run(0.4);
      final second = run(0.8);
      expect(first, isNot(orderedEquals(second)));

      // Repetir a primeira combinação tem de devolver exactamente o mesmo
      // resultado: a memoização por etapa não pode contaminar o estado.
      expect(run(0.4), orderedEquals(first));
    });
  });
}

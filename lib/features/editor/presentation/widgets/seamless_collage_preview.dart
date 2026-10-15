import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/brand_visual.dart';
import '../../../../core/utils/seamless_blend_curve.dart';
import '../../../../core/utils/seamless_blend_engine.dart';

/// Colagem ao vivo: a mesclagem e o arrasto das fotos não esperam o motor CPU.
class SeamlessCollagePreview extends StatefulWidget {
  const SeamlessCollagePreview({
    super.key,
    required this.imagePaths,
    required this.aspect,
    required this.fusionStrength,
    required this.photoPans,
    required this.onPhotoPanChanged,
  });

  final List<String> imagePaths;
  final CollageAspectPreset aspect;
  final double fusionStrength;
  final List<SeamlessPhotoPan> photoPans;
  final void Function(int index, SeamlessPhotoPan pan) onPhotoPanChanged;

  @override
  State<SeamlessCollagePreview> createState() => _SeamlessCollagePreviewState();
}

class _SeamlessCollagePreviewState extends State<SeamlessCollagePreview> {
  final Map<String, Size> _sizes = {};
  List<SeamlessPhotoPan> _pans = const [];
  int? _dragging;

  double get _presetAspectRatio => widget.aspect.widthOverHeight;

  @override
  void initState() {
    super.initState();
    _pans = List<SeamlessPhotoPan>.from(widget.photoPans);
    unawaited(_loadSizes());
  }

  @override
  void didUpdateWidget(SeamlessCollagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragging == null) {
      _pans = List<SeamlessPhotoPan>.from(widget.photoPans);
    }
    if (!_samePaths(oldWidget.imagePaths, widget.imagePaths)) {
      unawaited(_loadSizes());
    }
  }

  bool _samePaths(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _loadSizes() async {
    final paths = List<String>.from(widget.imagePaths);
    for (final path in paths) {
      if (_sizes.containsKey(path)) continue;
      try {
        final bytes = await File(path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final size = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        frame.image.dispose();
        codec.dispose();
        if (!mounted) return;
        setState(() => _sizes[path] = size);
      } catch (_) {
        // Sem tamanho, a foto fica centrada até o próximo carregamento.
      }
    }
  }

  SeamlessPhotoPan _panAt(int index) {
    if (index < 0 || index >= _pans.length) {
      return const SeamlessPhotoPan();
    }
    return _pans[index];
  }

  int _photoAt(Offset local, Size canvas, SeamlessSlotLayout layout) {
    final horizontal = layout.horizontal;
    final axis = horizontal ? canvas.width : canvas.height;
    if (layout.axisLength <= 0 || axis <= 0) return 0;
    final scale = axis / layout.axisLength;
    final slot = layout.slotMain * scale;
    final step = layout.step * scale;
    final pos = horizontal ? local.dx : local.dy;
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < layout.photoCount; i++) {
      final start = i * step;
      if (pos < start || pos > start + slot) continue;
      final dist = (pos - (start + slot / 2)).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  void _dragBy(int index, Offset delta, Size slotSize) {
    final path = widget.imagePaths[index];
    final source = _sizes[path];
    final frame = source == null
        ? null
        : SeamlessCoverFrame.measure(
            sourceWidth: source.width,
            sourceHeight: source.height,
            slotWidth: slotSize.width,
            slotHeight: slotSize.height,
          );
    final overflowX = frame?.overflowX ?? slotSize.width * 0.35;
    final overflowY = frame?.overflowY ?? slotSize.height * 0.35;
    final current = _panAt(index);
    var x = current.x;
    var y = current.y;
    if (overflowX > 1) {
      x = (x - 2 * delta.dx / overflowX).clamp(-1.0, 1.0);
    }
    if (overflowY > 1) {
      y = (y - 2 * delta.dy / overflowY).clamp(-1.0, 1.0);
    }
    final pan = SeamlessPhotoPan(x: x, y: y);
    setState(() {
      final pans = List<SeamlessPhotoPan>.from(_pans);
      while (pans.length <= index) {
        pans.add(const SeamlessPhotoPan());
      }
      pans[index] = pan;
      _pans = pans;
    });
    widget.onPhotoPanChanged(index, pan);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imagePaths.length < SeamlessBlendEngine.minPhotos) {
      return const _EmptyPreview();
    }

    final layout = SeamlessSlotLayout.compute(
      aspect: widget.aspect,
      photoCount: widget.imagePaths.length,
      fusionStrength: widget.fusionStrength,
      maxEdge: 4096,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final ratio = _presetAspectRatio;

        var width = maxW;
        var height = width / ratio;
        if (height > maxH) {
          height = maxH;
          width = height * ratio;
        }

        final canvas = Size(width, height);
        final horizontal = layout.horizontal;
        final axis = horizontal ? width : height;
        final scale = layout.axisLength == 0 ? 1.0 : axis / layout.axisLength;
        final slotMain = layout.slotMain * scale;
        final step = layout.step * scale;
        final overlap = layout.overlap * scale;

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) {
                  setState(() {
                    _dragging = _photoAt(details.localPosition, canvas, layout);
                  });
                },
                onPanUpdate: (details) {
                  final index = _dragging;
                  if (index == null) return;
                  final slotSize = horizontal
                      ? Size(slotMain, height)
                      : Size(width, slotMain);
                  _dragBy(index, details.delta, slotSize);
                },
                onPanEnd: (_) => setState(() => _dragging = null),
                onPanCancel: () => setState(() => _dragging = null),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var i = 0; i < widget.imagePaths.length; i++)
                      _slot(
                        index: i,
                        layout: layout,
                        canvas: canvas,
                        slotMain: slotMain,
                        step: step,
                        overlap: overlap,
                      ),
                    if (_dragging != null)
                      _dragFrame(
                        index: _dragging!,
                        horizontal: horizontal,
                        slotMain: slotMain,
                        step: step,
                        canvas: canvas,
                      ),
                    const Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: IgnorePointer(
                        child: _DragHint(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _slot({
    required int index,
    required SeamlessSlotLayout layout,
    required Size canvas,
    required double slotMain,
    required double step,
    required double overlap,
  }) {
    final horizontal = layout.horizontal;
    final origin = index * step;
    final slotW = horizontal ? slotMain : canvas.width;
    final slotH = horizontal ? canvas.height : slotMain;
    final pan = _panAt(index);
    final photo = _framedPhoto(
      path: widget.imagePaths[index],
      pan: pan,
      slotW: slotW,
      slotH: slotH,
    );
    final overlapFrac = slotMain <= 0 ? 0.0 : (overlap / slotMain).clamp(0.0, 1.0);
    final masked = index == 0 || overlapFrac <= 0.001
        ? photo
        : ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              return _incomingFade(
                horizontal: horizontal,
                overlapFraction: overlapFrac,
                fusion: widget.fusionStrength,
              ).createShader(bounds);
            },
            child: photo,
          );

    return Positioned(
      left: horizontal ? origin : 0,
      top: horizontal ? 0 : origin,
      width: slotW,
      height: slotH,
      child: masked,
    );
  }

  Widget _framedPhoto({
    required String path,
    required SeamlessPhotoPan pan,
    required double slotW,
    required double slotH,
  }) {
    final source = _sizes[path];
    if (source == null) {
      return Image.file(
        File(path),
        width: slotW,
        height: slotH,
        fit: BoxFit.cover,
        alignment: Alignment(pan.x, pan.y),
      );
    }

    final frame = SeamlessCoverFrame.measure(
      sourceWidth: source.width,
      sourceHeight: source.height,
      slotWidth: slotW,
      slotHeight: slotH,
    );
    final left = -frame.overflowX * (pan.x.clamp(-1.0, 1.0) + 1) / 2;
    final top = -frame.overflowY * (pan.y.clamp(-1.0, 1.0) + 1) / 2;

    return ClipRect(
      child: SizedBox(
        width: slotW,
        height: slotH,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: frame.scaledWidth,
              height: frame.scaledHeight,
              child: Image.file(
                File(path),
                fit: BoxFit.fill,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dragFrame({
    required int index,
    required bool horizontal,
    required double slotMain,
    required double step,
    required Size canvas,
  }) {
    final origin = index * step;
    return Positioned(
      left: horizontal ? origin : 0,
      top: horizontal ? 0 : origin,
      width: horizontal ? slotMain : canvas.width,
      height: horizontal ? canvas.height : slotMain,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary, width: 2),
          ),
        ),
      ),
    );
  }

  LinearGradient _incomingFade({
    required bool horizontal,
    required double overlapFraction,
    required double fusion,
  }) {
    final end = overlapFraction.clamp(0.0, 1.0);
    const samples = 10;
    final colors = <Color>[];
    final stops = <double>[];
    for (var s = 0; s <= samples; s++) {
      final t = s / samples;
      final pos = t * end;
      if (stops.isNotEmpty && pos <= stops.last + 0.0001) continue;
      stops.add(pos.clamp(0.0, 1.0));
      final weight = SeamlessBlendCurve.blendWeight(t, fusion);
      colors.add(
        Color.fromARGB((weight * 255).round().clamp(0, 255), 255, 255, 255),
      );
    }
    if (stops.last < 0.999) {
      stops.add(1);
      colors.add(const Color(0xFFFFFFFF));
    }
    return LinearGradient(
      begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
      end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    );
  }
}

class _DragHint extends StatelessWidget {
  const _DragHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC10213D),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            'Arraste a foto para reposicionar',
            style: BrandVisual.text(
              size: 12,
              weight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.view_agenda_outlined,
            size: 48,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Selecione pelo menos 2 fotos',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../../core/utils/seamless_blend_curve.dart';
import '../../../../core/utils/seamless_blend_engine.dart';

/// Preview gerado pelo mesmo motor CPU do export.
class SeamlessCollagePreview extends StatefulWidget {
  const SeamlessCollagePreview({
    super.key,
    required this.imagePaths,
    required this.aspect,
    required this.fusionStrength,
  });

  final List<String> imagePaths;
  final CollageAspectPreset aspect;
  final double fusionStrength;

  @override
  State<SeamlessCollagePreview> createState() => _SeamlessCollagePreviewState();
}

class _SeamlessCollagePreviewState extends State<SeamlessCollagePreview> {
  static const _engine = SeamlessBlendEngine();
  static const _previewMaxEdge = 720;

  Uint8List? _previewBytes;
  bool _isGenerating = false;
  Timer? _debounce;
  int _generation = 0;
  int _displayGeneration = 0;

  double get _presetAspectRatio => widget.aspect.widthOverHeight;

  @override
  void initState() {
    super.initState();
    _schedulePreview(immediate: true);
  }

  @override
  void didUpdateWidget(SeamlessCollagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_inputsChanged(oldWidget)) {
      _schedulePreview(immediate: _pathsChanged(oldWidget.imagePaths));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _inputsChanged(SeamlessCollagePreview old) {
    return _pathsChanged(old.imagePaths) ||
        old.aspect.family != widget.aspect.family ||
        old.aspect.orientation != widget.aspect.orientation ||
        old.fusionStrength != widget.fusionStrength;
  }

  bool _pathsChanged(List<String> previous) {
    final current = widget.imagePaths;
    if (previous.length != current.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (previous[i] != current[i]) return true;
    }
    return false;
  }

  void _schedulePreview({bool immediate = false}) {
    _debounce?.cancel();

    if (widget.imagePaths.length < SeamlessBlendEngine.minPhotos) {
      setState(() {
        _previewBytes = null;
        _isGenerating = false;
        _displayGeneration = ++_generation;
      });
      return;
    }

    if (immediate && mounted) {
      setState(() {
        _previewBytes = null;
        _isGenerating = true;
      });
    }

    if (immediate) {
      unawaited(_generatePreview());
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 40), () {
      unawaited(_generatePreview());
    });
  }

  Future<void> _generatePreview() async {
    if (widget.imagePaths.length < SeamlessBlendEngine.minPhotos) return;

    final generation = ++_generation;
    if (mounted) setState(() => _isGenerating = true);

    final paths = List<String>.from(widget.imagePaths);
    final aspect = widget.aspect;
    final fusion = widget.fusionStrength;

    try {
      final result = await _engine.blend(
        imagePaths: paths,
        config: SeamlessBlendConfig(
          aspect: aspect,
          fusionStrength: fusion,
          maxEdge: _previewMaxEdge,
          jpegQuality: 82,
        ),
      );

      if (!mounted || generation != _generation) return;

      final bytes = Uint8List.fromList(
        img.encodeJpg(result.image, quality: 82),
      );

      setState(() {
        _previewBytes = bytes;
        _displayGeneration = generation;
        _isGenerating = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _previewBytes = null;
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imagePaths.length < SeamlessBlendEngine.minPhotos) {
      return const _EmptyPreview();
    }

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

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _previewBytes == null
                      ? const ColoredBox(
                          color: Color(0x11000000),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Image.memory(
                          _previewBytes!,
                          key: ValueKey(_displayGeneration),
                          fit: BoxFit.cover,
                          gaplessPlayback: false,
                        ),
                ),
                if (_isGenerating && _previewBytes != null)
                  const ColoredBox(
                    color: Colors.black26,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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

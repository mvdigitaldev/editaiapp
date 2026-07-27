import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../../core/utils/seamless_blend_engine.dart';

/// Preview gerado pelo mesmo motor CPU do export — comportamento idêntico
/// para 2, 3 ou mais fotos.
class SeamlessCollagePreview extends StatefulWidget {
  const SeamlessCollagePreview({
    super.key,
    required this.imagePaths,
    required this.layout,
    required this.fusionStrength,
  });

  final List<String> imagePaths;
  final CollageLayout layout;
  final double fusionStrength;

  @override
  State<SeamlessCollagePreview> createState() => _SeamlessCollagePreviewState();
}

class _SeamlessCollagePreviewState extends State<SeamlessCollagePreview> {
  static const _engine = SeamlessBlendEngine();
  static const _previewMaxCrossAxis = 720;

  Uint8List? _previewBytes;
  double? _aspectRatio;
  bool _isGenerating = false;
  Timer? _debounce;
  int _generation = 0;
  int _displayGeneration = 0;

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
        old.layout != widget.layout ||
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
        _aspectRatio = null;
        _isGenerating = false;
        _displayGeneration = ++_generation;
      });
      return;
    }

    // Descarta preview antigo imediatamente ao trocar fotos/ordem.
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

    // Snapshot — evita ler lista mutável durante o blend async.
    final paths = List<String>.from(widget.imagePaths);
    final layout = widget.layout;
    final fusion = widget.fusionStrength;

    try {
      final result = await _engine.blend(
        imagePaths: paths,
        config: SeamlessBlendConfig(
          layout: layout,
          fusionStrength: fusion,
          maxCrossAxis: _previewMaxCrossAxis,
          jpegQuality: 82,
        ),
      );

      if (!mounted || generation != _generation) return;

      final bytes = Uint8List.fromList(
        img.encodeJpg(result.image, quality: 82),
      );

      setState(() {
        _previewBytes = bytes;
        _aspectRatio = result.width / result.height;
        _displayGeneration = generation;
        _isGenerating = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _previewBytes = null;
        _aspectRatio = null;
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imagePaths.length < SeamlessBlendEngine.minPhotos) {
      return const _EmptyPreview();
    }

    if (_previewBytes == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final ratio = _aspectRatio ?? 1;

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
                  child: Image.memory(
                    _previewBytes!,
                    key: ValueKey(_displayGeneration),
                    fit: BoxFit.contain,
                    gaplessPlayback: false,
                  ),
                ),
                if (_isGenerating)
                  Container(
                    color: Colors.black26,
                    child: const Center(
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

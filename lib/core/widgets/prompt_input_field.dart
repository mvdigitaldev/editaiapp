import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/voice_prompt_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'voice_recording_waveform.dart';

/// Campo de prompt com botão de mic por voz.
///
/// - Toque: liga/desliga a gravação
/// - Segurar: grava enquanto pressiona e para ao soltar
/// - Enquanto grava: mostra waveform + timer estilo WhatsApp
class PromptInputField extends StatefulWidget {
  const PromptInputField({
    super.key,
    required this.controller,
    this.hintText,
    this.maxLines = 4,
    this.minLines,
    this.onChanged,
    this.enabled = true,
    this.decoration,
    this.style,
    this.hintStyle,
    this.contentPadding = const EdgeInsets.all(16),
    this.showBorderContainer = true,
    this.micInFooter = false,
    this.footerLeading,
  });

  final TextEditingController controller;
  final String? hintText;
  final int maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Se informado, substitui a decoration padrão do TextField (border none).
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final EdgeInsetsGeometry contentPadding;

  /// Container com borda arredondada (padrão das telas de edição).
  final bool showBorderContainer;

  /// Quando true, o mic fica numa barra abaixo do TextField (ex.: AIPromptEditor).
  final bool micInFooter;

  /// Conteúdo à esquerda na barra de footer (junto ao mic).
  final Widget? footerLeading;

  @override
  State<PromptInputField> createState() => _PromptInputFieldState();
}

class _PromptInputFieldState extends State<PromptInputField>
    with SingleTickerProviderStateMixin {
  final VoicePromptService _voice = VoicePromptService();

  bool _listening = false;
  /// true quando a sessão atual foi iniciada por long-press (para ao soltar).
  bool _holdMode = false;
  String _baseText = '';
  double _soundLevelDb = -50;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _pulse.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _mergeTranscript(String base, String words) {
    final trimmedWords = words.trim();
    if (trimmedWords.isEmpty) return base;
    final trimmedBase = base.trimRight();
    if (trimmedBase.isEmpty) return trimmedWords;
    return '$trimmedBase $trimmedWords';
  }

  void _beginRecordingUi() {
    _startedAt = DateTime.now();
    _elapsed = Duration.zero;
    _soundLevelDb = -50;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt!);
      });
    });
    _pulse.repeat(reverse: true);
  }

  void _endRecordingUi() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _startedAt = null;
    _elapsed = Duration.zero;
    _soundLevelDb = -50;
    _pulse.stop();
    _pulse.reset();
  }

  Future<void> _startListening() async {
    if (!widget.enabled || _listening) return;

    HapticFeedback.mediumImpact();
    _baseText = widget.controller.text;

    final started = await _voice.startListening(
      onResult: (words, isFinal) {
        if (!mounted) return;
        final merged = _mergeTranscript(_baseText, words);
        widget.controller.value = TextEditingValue(
          text: merged,
          selection: TextSelection.collapsed(offset: merged.length),
        );
        widget.onChanged?.call(merged);
      },
      onSoundLevel: (level) {
        if (!mounted || !_listening) return;
        setState(() => _soundLevelDb = level);
      },
      onError: (error) {
        if (!mounted) return;
        // Ignora erros leves de "não ouvi nada" enquanto ainda está gravando
        // por toque (usuário pode continuar falando).
        final code = error.toLowerCase();
        final soft = code.contains('timeout') ||
            code.contains('no_match') ||
            code.contains('no_speech');
        if (soft && _listening && !_holdMode) {
          return;
        }

        setState(() {
          _listening = false;
          _holdMode = false;
        });
        _endRecordingUi();
        _showMessage(VoicePromptService.friendlyError(error));
      },
    );

    if (!mounted) return;

    if (!started) {
      _showMessage(
        VoicePromptService.friendlyError(_voice.lastInitError),
      );
      return;
    }

    setState(() => _listening = true);
    _beginRecordingUi();
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    HapticFeedback.lightImpact();
    await _voice.stopListening();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _holdMode = false;
    });
    _endRecordingUi();
  }

  Future<void> _onMicTap() async {
    if (!widget.enabled) return;
    if (_listening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _onHoldStart() async {
    if (!widget.enabled) return;
    _holdMode = true;
    if (!_listening) {
      await _startListening();
    }
  }

  Future<void> _onHoldEnd() async {
    if (!_holdMode) return;
    await _stopListening();
  }

  Widget _buildMicButton({required bool isDark}) {
    const activeColor = AppColors.error;
    final idleColor =
        isDark ? AppColors.textTertiary : AppColors.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onMicTap,
      onLongPressStart: (_) => _onHoldStart(),
      onLongPressEnd: (_) => _onHoldEnd(),
      onLongPressCancel: () => _onHoldEnd(),
      child: Tooltip(
        message: _listening
            ? 'Toque para parar'
            : 'Toque ou segure para falar',
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final scale = _listening ? 1.0 + (_pulse.value * 0.12) : 1.0;
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: _listening
                ? BoxDecoration(
                    color: activeColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  )
                : null,
            child: Icon(
              _listening ? Icons.stop_rounded : Icons.mic_none,
              color: _listening ? activeColor : idleColor,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: VoiceRecordingWaveform(
              levelDb: _soundLevelDb,
              elapsed: _elapsed,
            ),
          ),
          _buildMicButton(isDark: Theme.of(context).brightness == Brightness.dark),
        ],
      ),
    );
  }

  InputDecoration _defaultDecoration(bool isDark) {
    return InputDecoration(
      hintText: widget.hintText,
      hintStyle: widget.hintStyle ??
          AppTextStyles.bodyLarge.copyWith(
            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
          ),
      border: InputBorder.none,
      contentPadding: widget.contentPadding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStyle = widget.style ??
        AppTextStyles.bodyLarge.copyWith(
          color: isDark ? AppColors.textLight : AppColors.textPrimary,
        );

    final field = TextField(
      controller: widget.controller,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      enabled: widget.enabled && !_listening,
      onChanged: widget.onChanged,
      style: textStyle,
      decoration: widget.decoration ?? _defaultDecoration(isDark),
    );

    final mic = _buildMicButton(isDark: isDark);

    late final Widget content;
    if (widget.micInFooter) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          Divider(
            height: 1,
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
          if (_listening)
            _buildRecordingBar()
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  if (widget.footerLeading != null) ...[
                    Expanded(child: widget.footerLeading!),
                  ] else
                    const Spacer(),
                  mic,
                ],
              ),
            ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_listening) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                widget.controller.text.trim().isEmpty
                    ? 'Ouvindo…'
                    : widget.controller.text,
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
            _buildRecordingBar(),
          ] else
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: field,
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: mic,
                ),
              ],
            ),
        ],
      );
    }

    if (!widget.showBorderContainer) {
      return content;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _listening
              ? AppColors.error.withValues(alpha: 0.7)
              : (isDark ? AppColors.borderDark : AppColors.border),
        ),
      ),
      child: content,
    );
  }
}

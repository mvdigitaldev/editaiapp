import 'dart:async';
import 'package:flutter/material.dart';

/// Widget que exibe texto com efeito de digitar e apagar letra por letra.
class TypewriterWithDeleteText extends StatefulWidget {
  const TypewriterWithDeleteText({
    super.key,
    required this.phrases,
    required this.textStyle,
    this.typingSpeed = const Duration(milliseconds: 100),
    this.deletingSpeed = const Duration(milliseconds: 80),
    this.pauseAfterTyping = const Duration(milliseconds: 1500),
    this.pauseAfterDeleting = const Duration(milliseconds: 500),
    this.cursor = '|',
  });

  final List<String> phrases;
  final TextStyle textStyle;
  final Duration typingSpeed;
  final Duration deletingSpeed;
  final Duration pauseAfterTyping;
  final Duration pauseAfterDeleting;
  final String cursor;

  @override
  State<TypewriterWithDeleteText> createState() =>
      _TypewriterWithDeleteTextState();
}

class _TypewriterWithDeleteTextState extends State<TypewriterWithDeleteText> {
  int _phraseIndex = 0;
  int _charIndex = 0;
  bool _isDeleting = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleNextTick() {
    _timer?.cancel();
    final phrase = widget.phrases[_phraseIndex];
    final phraseLength = phrase.length;

    if (_isDeleting) {
      if (_charIndex > 0) {
        _timer = Timer(widget.deletingSpeed, () {
          if (mounted) {
            setState(() => _charIndex--);
            _scheduleNextTick();
          }
        });
      } else {
        _timer = Timer(widget.pauseAfterDeleting, () {
          if (mounted) {
            setState(() {
              _isDeleting = false;
              _phraseIndex = (_phraseIndex + 1) % widget.phrases.length;
            });
            _scheduleNextTick();
          }
        });
      }
    } else {
      if (_charIndex < phraseLength) {
        _timer = Timer(widget.typingSpeed, () {
          if (mounted) {
            setState(() => _charIndex++);
            _scheduleNextTick();
          }
        });
      } else {
        _timer = Timer(widget.pauseAfterTyping, () {
          if (mounted) {
            setState(() => _isDeleting = true);
            _scheduleNextTick();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phrase = widget.phrases[_phraseIndex];
    final displayText = phrase.substring(0, _charIndex);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: displayText, style: widget.textStyle),
          TextSpan(
            text: widget.cursor,
            style: widget.textStyle.copyWith(
              color: (widget.textStyle.color ?? const Color(0xFF9E9E9E)).withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

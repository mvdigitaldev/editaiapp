import 'package:flutter/material.dart';

import '../../l10n/body_reshape_labels.dart';

/// «Travar fundo» sobre a foto, como o «Bloqueio de fundo» do Meitu: pílula
/// escura, diamante do plano pago e switch pequeno. Sem plano pago o switch
/// fica desligado e o toque chama [onLocked].
class BodyBackgroundLockPill extends StatelessWidget {
  const BodyBackgroundLockPill({
    super.key,
    required this.value,
    required this.allowed,
    required this.enabled,
    required this.onChanged,
    this.onLocked,
  });

  static const _premium = Color(0xFFFF4D8D);

  final bool value;
  final bool allowed;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onLocked;

  void _toggle() {
    if (!enabled) {
      return;
    }
    if (!allowed) {
      onLocked?.call();
      return;
    }
    onChanged(!value);
  }

  @override
  Widget build(BuildContext context) {
    final on = allowed && value;
    return Semantics(
      button: true,
      toggled: on,
      label: BodyReshapeLabels.backgroundLock,
      child: GestureDetector(
        key: const ValueKey('body_bg_lock_pill'),
        onTap: _toggle,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 5, 5, 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.diamond_rounded, size: 14, color: _premium),
                const SizedBox(width: 6),
                const Text(
                  BodyReshapeLabels.backgroundLock,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                _MiniSwitch(on: on),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    const width = 34.0;
    const height = 20.0;
    const knob = 16.0;
    return AnimatedContainer(
      key: const ValueKey('body_bg_lock_switch'),
      duration: const Duration(milliseconds: 160),
      width: width,
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: on
            ? BodyBackgroundLockPill._premium
            : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: knob,
          height: knob,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

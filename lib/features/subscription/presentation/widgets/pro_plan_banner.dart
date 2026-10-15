import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_visual.dart';
import '../pro_plan_invite.dart';

enum ProBannerKind { principal, compact, opportunity, offer }

/// Convite visual ao plano Pro. O toque abre os planos; o fecho é opcional.
class ProPlanBanner extends StatelessWidget {
  const ProPlanBanner({
    super.key,
    required this.kind,
    required this.highlights,
    required this.onTap,
    this.onClose,
  });

  final ProBannerKind kind;
  final ProBannerHighlights highlights;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      ProBannerKind.principal => _PrincipalBanner(
          highlights: highlights,
          onTap: onTap,
          onClose: onClose,
        ),
      ProBannerKind.compact => _CompactBanner(
          highlights: highlights,
          onTap: onTap,
          onClose: onClose,
        ),
      ProBannerKind.opportunity => _OpportunityBanner(
          onTap: onTap,
          onClose: onClose,
        ),
      ProBannerKind.offer => _OfferBanner(
          onTap: onTap,
          onClose: onClose,
        ),
    };
  }
}

class _Benefit {
  const _Benefit(this.icon, this.label);
  final IconData icon;
  final String label;
}

List<_Benefit> _benefits(ProBannerHighlights highlights) {
  return [
    const _Benefit(Icons.auto_awesome, 'Edições\ncom IA'),
    if (highlights.morePhotos)
      const _Benefit(Icons.photo_library_outlined, 'Mais fotos\nguardadas'),
    const _Benefit(Icons.accessibility_new, 'Ajustes\nde corpo'),
    if (highlights.moreCredits)
      const _Benefit(Icons.toll_outlined, 'Mais\ncréditos'),
  ];
}

class _PrincipalBanner extends StatelessWidget {
  const _PrincipalBanner({
    required this.highlights,
    required this.onTap,
    required this.onClose,
  });

  final ProBannerHighlights highlights;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      onTap: onTap,
      onClose: onClose,
      closeColor: Colors.white,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A4DFF), Color(0xFF10213D), Color(0xFF0A6FE0)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProPill(),
          const SizedBox(height: 12),
          Text(
            'Leve suas fotos',
            style: BrandVisual.title(size: 26, color: Colors.white, height: 1.05),
          ),
          Text(
            'para outro nível',
            style: BrandVisual.title(
              size: 26,
              color: const Color(0xFF7DEBFF),
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Explore mais possibilidades.',
            style: BrandVisual.text(
              size: 14,
              weight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 14),
          _BenefitRow(benefits: _benefits(highlights), onDark: true),
          const SizedBox(height: 14),
          const _BannerButton(label: 'Conhecer o Plano Pro'),
        ],
      ),
    );
  }
}

class _CompactBanner extends StatelessWidget {
  const _CompactBanner({
    required this.highlights,
    required this.onTap,
    required this.onClose,
  });

  final ProBannerHighlights highlights;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      onTap: onTap,
      onClose: onClose,
      closeColor: BrandVisual.navy,
      gradient: const LinearGradient(
        colors: [Color(0xFFF7FBFF), Color(0xFFE4F0FF)],
      ),
      child: Row(
        children: [
          const _IconBadge(icon: Icons.workspace_premium_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Desbloqueie o Plano Pro',
                  style: BrandVisual.title(size: 16, height: 1.15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Conheça o Plano Pro',
                  style: BrandVisual.text(size: 13, color: const Color(0xFF3D5270)),
                ),
                const SizedBox(height: 8),
                _BenefitRow(benefits: _benefits(highlights), onDark: false),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _ArrowDisc(),
        ],
      ),
    );
  }
}

class _OpportunityBanner extends StatelessWidget {
  const _OpportunityBanner({required this.onTap, required this.onClose});

  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      onTap: onTap,
      onClose: onClose,
      closeColor: Colors.white,
      gradient: const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFF123A86), Color(0xFF168BFF)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBadge(
                icon: Icons.bolt_rounded,
                background: Color(0x33168BFF),
                iconColor: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: BrandVisual.title(
                      size: 18,
                      color: Colors.white,
                      height: 1.15,
                    ),
                    children: [
                      const TextSpan(text: 'Mais possibilidades\n'),
                      TextSpan(
                        text: 'com o Plano Pro',
                        style: BrandVisual.title(
                          size: 18,
                          color: const Color(0xFF7DEBFF),
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Desbloqueie esse recurso',
            style: BrandVisual.text(
              size: 13,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerRight,
            child: _BannerButton(label: 'Quero o Plano Pro', compact: true),
          ),
        ],
      ),
    );
  }
}

class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.onTap, required this.onClose});

  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      onTap: onTap,
      onClose: onClose,
      closeColor: BrandVisual.navy,
      gradient: const LinearGradient(
        colors: [Color(0xFFFFF4E5), Color(0xFFE7F2FF)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBadge(icon: Icons.card_giftcard_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Oferta especial do Plano Pro',
                  style: BrandVisual.title(size: 16, height: 1.15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Continue criando com o Pro',
            style: BrandVisual.text(size: 13, color: const Color(0xFF3D5270)),
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerRight,
            child: _BannerButton(label: 'Aproveitar agora', compact: true),
          ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.gradient,
    required this.child,
    required this.onTap,
    required this.onClose,
    required this.closeColor,
  });

  final Gradient gradient;
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final Color closeColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: BrandVisual.navy.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  onClose != null ? 36 : 18,
                  18,
                  16,
                ),
                child: child,
              ),
              if (onClose != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: Icon(Icons.close, size: 18, color: closeColor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProPill extends StatelessWidget {
  const _ProPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: BrandVisual.blue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            'Plano Pro',
            style: BrandVisual.text(
              size: 12,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    this.background = const Color(0xFF168BFF),
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final Color background;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: iconColor, size: 28),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefits, required this.onDark});

  final List<_Benefit> benefits;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final benefit in benefits)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: onDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : BrandVisual.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  benefit.icon,
                  size: 16,
                  color: onDark ? Colors.white : BrandVisual.blue,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                benefit.label,
                style: BrandVisual.text(
                  size: 11,
                  weight: FontWeight.w700,
                  height: 1.15,
                  color: onDark ? Colors.white : BrandVisual.navy,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        '$label →',
        style: BrandVisual.text(
          size: compact ? 12 : 14,
          weight: FontWeight.w800,
          color: BrandVisual.blue,
        ),
      ),
    );
  }
}

class _ArrowDisc extends StatelessWidget {
  const _ArrowDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: BrandVisual.blue,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
    );
  }
}

/// Faixa compacta da home. Some sozinha quando não é para a conta grátis.
class ProPlanHomeBanner extends ConsumerWidget {
  const ProPlanHomeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(proCompactBannerVisibleProvider);
    final highlights = ref.watch(proBannerHighlightsProvider).valueOrNull ??
        ProBannerHighlights.fallback;

    return visible.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (show) {
        if (!show) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: ProPlanBanner(
            kind: ProBannerKind.compact,
            highlights: highlights,
            onTap: () => openProPlans(context),
            onClose: () => unawaited(dismissCompactBanner(ref)),
          ),
        );
      },
    );
  }
}

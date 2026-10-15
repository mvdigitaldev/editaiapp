import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_visual.dart';
import '../pro_plan_invite.dart';

enum ProBannerKind { principal, compact, opportunity, offer }

/// Cartão flutuante. O fundo escuro fica no diálogo; aqui é só o anúncio.
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
    final card = switch (kind) {
      ProBannerKind.principal => _PrincipalCard(onTap: onTap),
      ProBannerKind.compact => _CompactCard(
          highlights: highlights,
          onTap: onTap,
        ),
      ProBannerKind.opportunity => _OpportunityCard(onTap: onTap),
      ProBannerKind.offer => _OfferCard(onTap: onTap),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _FloatClose(onPressed: onClose),
        const SizedBox(height: 10),
        card,
      ],
    );
  }
}

/// Escurece a tela. Só fecha no X ou no botão de contratar.
Future<bool> showProBannerOverlay({
  required BuildContext context,
  required ProBannerKind kind,
  required ProBannerHighlights highlights,
}) async {
  final tapped = await showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: 'Convite do Plano Pro',
    barrierColor: const Color(0xD9071426),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, __) {
      return SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            child: ProPlanBanner(
              kind: kind,
              highlights: highlights,
              onTap: () => Navigator.of(dialogContext).pop(true),
              onClose: () => Navigator.of(dialogContext).pop(false),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return tapped == true;
}

/// Na home, o compacto cobre a tela em vez de entrar no scroll.
class ProPlanHomeOfferHost extends ConsumerStatefulWidget {
  const ProPlanHomeOfferHost({super.key});

  @override
  ConsumerState<ProPlanHomeOfferHost> createState() =>
      _ProPlanHomeOfferHostState();
}

class _ProPlanHomeOfferHostState extends ConsumerState<ProPlanHomeOfferHost> {
  bool _presented = false;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(proCompactBannerVisibleProvider, (_, next) {
      if (next.valueOrNull == true) {
        _schedule();
      } else if (next.valueOrNull == false) {
        _presented = false;
      }
    });
    if (TickerMode.valuesOf(context).enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
    }
    return const SizedBox.shrink();
  }

  void _schedule() {
    if (!mounted || _presented || _open) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    if (ref.read(proCompactBannerVisibleProvider).valueOrNull != true) return;
    _presented = true;
    _open = true;
    final highlights = ref.read(proBannerHighlightsProvider).valueOrNull ??
        ProBannerHighlights.fallback;
    showProBannerOverlay(
      context: context,
      kind: ProBannerKind.principal,
      highlights: highlights,
    ).then((tapped) async {
      _open = false;
      if (!mounted) return;
      if (tapped) {
        unawaited(recordProBannerClick(ProBannerKind.principal));
        openProPlans(context);
      } else {
        await dismissCompactBanner(ref);
      }
    });
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
    if (highlights.moreCredits)
      const _Benefit(Icons.layers_outlined, 'Mais\ncréditos'),
    const _Benefit(Icons.workspace_premium_outlined, 'Recursos\nexclusivos'),
  ];
}

class _PrincipalCard extends StatelessWidget {
  const _PrincipalCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            'assets/branding/pro_banner_principal.jpg',
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
    );
  }
}

class _CompactCard extends StatelessWidget {
  const _CompactCard({required this.highlights, required this.onTap});

  final ProBannerHighlights highlights;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PromoCard(
      onTap: onTap,
      radius: 28,
      gradient: const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFF3F8FF), Color(0xFFE4EEFF)],
      ),
      shadow: const Color(0x33168BFF),
      child: Column(
        children: [
          Row(
            children: [
              const _CrownTile(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: BrandVisual.title(size: 18, height: 1.15),
                        children: [
                          const TextSpan(text: 'Desbloqueie o '),
                          TextSpan(
                            text: 'Plano Pro',
                            style: BrandVisual.title(
                              size: 18,
                              height: 1.15,
                              color: BrandVisual.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Conheça o Plano Pro',
                      style: BrandVisual.text(
                        size: 13,
                        color: const Color(0xFF5C6B82),
                      ),
                    ),
                  ],
                ),
              ),
              const _ArrowDisc(),
            ],
          ),
          const SizedBox(height: 14),
          _ChipRow(benefits: _benefits(highlights), onDark: false),
        ],
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PromoCard(
      onTap: onTap,
      radius: 28,
      gradient: const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFF102A78), Color(0xFF1A4FE0), Color(0xFF168BFF)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.bolt_rounded, color: Color(0xFFB9D4FF), size: 36),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: BrandVisual.title(
                          size: 20,
                          color: Colors.white,
                          height: 1.1,
                        ),
                        children: [
                          const TextSpan(text: 'Mais possibilidades\n'),
                          TextSpan(
                            text: 'com o Plano Pro',
                            style: BrandVisual.title(
                              size: 20,
                              color: const Color(0xFF5CEBFF),
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use a IA para criar, editar e transformar suas fotos.',
                      style: BrandVisual.text(
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              _MiniPhoto(
                asset: 'assets/home/home_preview_bg.png',
                angle: -0.08,
              ),
              SizedBox(width: 8),
              _MiniPhoto(
                asset: 'assets/home/retoque_rosto.png',
                angle: 0.06,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerRight,
            child: _Cta(label: 'Quero o Plano Pro', filled: true),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PromoCard(
      onTap: onTap,
      radius: 28,
      gradient: const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFFFF1D8), Color(0xFFF4E4FF), Color(0xFFE4E9FF)],
      ),
      shadow: const Color(0x33B388FF),
      child: Column(
        children: [
          Row(
            children: [
              const _GiftBadge(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: BrandVisual.title(size: 18, height: 1.15),
                        children: [
                          const TextSpan(text: 'Oferta especial do '),
                          TextSpan(
                            text: 'Plano Pro',
                            style: BrandVisual.title(
                              size: 18,
                              height: 1.15,
                              color: BrandVisual.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Desbloqueie edições com IA e recursos exclusivos.',
                      style: BrandVisual.text(
                        size: 13,
                        color: const Color(0xFF3D5270),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerRight,
            child: _Cta(label: 'Aproveitar agora', filled: true),
          ),
        ],
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.child,
    required this.onTap,
    required this.gradient,
    required this.radius,
    this.shadow = const Color(0x66071426),
  });

  final Widget child;
  final VoidCallback onTap;
  final Gradient gradient;
  final double radius;
  final Color shadow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: shadow,
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FloatClose extends StatelessWidget {
  const _FloatClose({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 8,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.close, size: 18, color: BrandVisual.navy),
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.benefits, required this.onDark});

  final List<_Benefit> benefits;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < benefits.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _Chip(benefit: benefits[i], onDark: onDark)),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.benefit, required this.onDark});

  final _Benefit benefit;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final iconColor = onDark ? Colors.white : BrandVisual.blue;
    final labelColor = onDark ? Colors.white : BrandVisual.navy;
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: onDark ? const Color(0xFF2E66F6) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: onDark
                ? null
                : [
                    BoxShadow(
                      color: BrandVisual.blue.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Icon(benefit.icon, color: iconColor, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          benefit.label,
          textAlign: TextAlign.center,
          style: BrandVisual.text(
            size: 10,
            weight: FontWeight.w700,
            height: 1.15,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.filled});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final background = filled ? BrandVisual.blue : Colors.white;
    final foreground = filled ? Colors.white : BrandVisual.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        '$label  →',
        style: BrandVisual.text(
          size: 14,
          weight: FontWeight.w800,
          color: foreground,
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
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        color: BrandVisual.blue,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x55168BFF),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 24),
    );
  }
}

class _CrownTile extends StatelessWidget {
  const _CrownTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4DA3FF), Color(0xFF166BFF)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55168BFF),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.workspace_premium, color: Colors.white, size: 34),
    );
  }
}

class _GiftBadge extends StatelessWidget {
  const _GiftBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(top: 0, right: 0, child: _Star(size: 10)),
          const Positioned(bottom: 6, left: -2, child: _Star(size: 8)),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7EB6FF), Color(0xFF2F6BFF)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x552F6BFF),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 34),
          ),
        ],
      ),
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Icon(Icons.auto_awesome, size: size, color: const Color(0xFFFFC857)),
    );
  }
}

class _MiniPhoto extends StatelessWidget {
  const _MiniPhoto({
    required this.asset,
    this.alignment = Alignment.center,
    this.angle = 0,
    this.badge,
    this.badgeOnDark = false,
  });

  final String asset;
  final Alignment alignment;
  final double angle;
  final String? badge;
  final bool badgeOnDark;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 72,
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(asset, fit: BoxFit.cover, alignment: alignment),
              if (badge != null)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeOnDark ? const Color(0xCC10213D) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: BrandVisual.text(
                        size: 9,
                        weight: FontWeight.w800,
                        color: badgeOnDark ? Colors.white : BrandVisual.navy,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

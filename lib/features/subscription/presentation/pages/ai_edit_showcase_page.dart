import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/enable_plans_provider.dart';
import '../../../../core/theme/brand_visual.dart';
import '../../../../core/widgets/comparison_slider.dart';
import '../../data/models/plan_model.dart';
import 'subscription_page.dart';

class _ShowcaseExample {
  const _ShowcaseExample({
    required this.phrase,
    required this.beforeAsset,
    required this.afterAsset,
  });

  final String phrase;
  final String beforeAsset;
  final String afterAsset;
}

const _examples = <_ShowcaseExample>[
  _ShowcaseExample(
    phrase: 'Trocar o fundo e fazer montagens',
    beforeAsset: 'assets/ai_showcase/fundo_antes.png',
    afterAsset: 'assets/ai_showcase/fundo_depois.png',
  ),
  _ShowcaseExample(
    phrase: 'Remover pessoas indesejadas',
    beforeAsset: 'assets/ai_showcase/pessoas_antes.png',
    afterAsset: 'assets/ai_showcase/pessoas_depois.png',
  ),
  _ShowcaseExample(
    phrase: 'Restaurar suas fotos',
    beforeAsset: 'assets/ai_showcase/restaurar_antes.png',
    afterAsset: 'assets/ai_showcase/restaurar_depois.png',
  ),
];

const _benefits = <({IconData icon, Color color, String title, String detail})>[
  (
    icon: Icons.photo_outlined,
    color: Color(0xFF22C55E),
    title: 'Trocar o fundo',
    detail: 'Coloque sua foto em cenários incríveis.',
  ),
  (
    icon: Icons.auto_awesome_mosaic_outlined,
    color: Color(0xFF8B5CF6),
    title: 'Criar montagens',
    detail: 'Combine várias fotos como quiser.',
  ),
  (
    icon: Icons.auto_fix_high,
    color: Color(0xFFEC4899),
    title: 'Pedir o que quiser',
    detail: 'Descreva com texto e a IA cria para você.',
  ),
];

PlanModel? _planWithCredits(List<PlanModel> plans, int credits) {
  final match = plans.where((plan) => !plan.isFree && plan.addCredit == credits);
  final monthly = match.where(
    (plan) => plan.durationMonths == null || plan.durationMonths! <= 1,
  );
  if (monthly.isNotEmpty) return monthly.first;
  if (match.isNotEmpty) return match.first;
  return null;
}

String _reais(double value) {
  if (value == value.roundToDouble()) return 'R\$${value.toInt()}';
  return 'R\$${value.toStringAsFixed(2).replaceAll('.', ',')}';
}

class AiEditShowcasePage extends ConsumerStatefulWidget {
  const AiEditShowcasePage({super.key});

  @override
  ConsumerState<AiEditShowcasePage> createState() => _AiEditShowcasePageState();
}

class _AiEditShowcasePageState extends ConsumerState<AiEditShowcasePage> {
  int _step = 0;
  bool _leaving = false;

  bool get _onOffer => _step >= _examples.length;

  void _leaveBecausePlansAreOff() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    });
  }

  void _next() {
    if (_step >= _examples.length) return;
    setState(() => _step += 1);
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step -= 1);
  }

  void _close() {
    Navigator.of(context).pop();
  }

  Future<void> _subscribe() async {
    final plansOn = await ref.read(enablePlansProvider.future);
    if (!mounted || !plansOn) return;
    final plans = await ref.read(activePlansProvider.future);
    if (!mounted) return;
    final link = _planWithCredits(plans, 200)?.linkPayment;
    if (link == null || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este plano não possui link de pagamento configurado.'),
        ),
      );
      return;
    }
    await Navigator.of(context).pushNamed('/checkout', arguments: link);
  }

  @override
  Widget build(BuildContext context) {
    final plansEnabled = ref.watch(enablePlansProvider);
    return plansEnabled.when(
      loading: () => const _ShowcaseFrame(
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
      error: (_, __) {
        _leaveBecausePlansAreOff();
        return const _ShowcaseFrame(child: SizedBox.shrink());
      },
      data: (enabled) {
        if (!enabled) {
          _leaveBecausePlansAreOff();
          return const _ShowcaseFrame(child: SizedBox.shrink());
        }
        return _ShowcaseFrame(
          child: _onOffer ? _buildOffer() : _buildExample(),
        );
      },
    );
  }

  Widget _buildExample() {
    final example = _examples[_step];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          _TopBar(onBack: _back),
          const SizedBox(height: 8),
          if (_step == 0)
            const _IntroHeadline()
          else
            Text(
              example.phrase,
              textAlign: TextAlign.center,
              style: BrandVisual.title(size: 28, color: Colors.white, height: 1.15),
            ),
          const SizedBox(height: 10),
          Text(
            'Arraste para o lado e veja a transformação.',
            textAlign: TextAlign.center,
            style: BrandVisual.text(
              size: 15,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _AspectCompare(
              key: ValueKey(example.beforeAsset),
              beforeAsset: example.beforeAsset,
              afterAsset: example.afterAsset,
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryPill(
            label: _step == _examples.length - 1
                ? 'Desbloquear a IA'
                : 'Ver próximo exemplo',
            onPressed: _next,
          ),
          const SizedBox(height: 14),
          _StepDots(count: _examples.length, index: _step),
          const SizedBox(height: 8),
          Text(
            'Exemplo ${_step + 1} de ${_examples.length}',
            style: BrandVisual.text(
              size: 13,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffer() {
    final plansAsync = ref.watch(activePlansProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _BackButton(onPressed: _back),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              children: [
                const _OfferHeader(),
                const SizedBox(height: 18),
                plansAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (plans) => _PlanOfferCard(
                    plan: _planWithCredits(plans, 200),
                  ),
                ),
                const SizedBox(height: 18),
                _PrimaryPill(
                  label: 'Eu quero',
                  pulse: true,
                  onPressed: () {
                    _subscribe();
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _close,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.85),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      'Agora não',
                      style: BrandVisual.text(
                        size: 16,
                        weight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AspectCompare extends StatefulWidget {
  const _AspectCompare({
    super.key,
    required this.beforeAsset,
    required this.afterAsset,
  });

  final String beforeAsset;
  final String afterAsset;

  @override
  State<_AspectCompare> createState() => _AspectCompareState();
}

class _AspectCompareState extends State<_AspectCompare> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _loadAspect();
  }

  @override
  void didUpdateWidget(_AspectCompare oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beforeAsset != widget.beforeAsset) {
      _aspect = null;
      _loadAspect();
    }
  }

  Future<void> _loadAspect() async {
    final asset = widget.beforeAsset;
    final stream = AssetImage(asset).resolve(const ImageConfiguration());
    final completer = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info);
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    try {
      final info = await completer.future;
      if (!mounted || asset != widget.beforeAsset) return;
      final width = info.image.width;
      final height = info.image.height;
      if (width <= 0 || height <= 0) return;
      setState(() => _aspect = width / height);
    } catch (_) {
      if (!mounted || asset != widget.beforeAsset) return;
      setState(() => _aspect = 3 / 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspect;
    if (aspect == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const inset = 18.0;
        final maxW = constraints.maxWidth - inset;
        final maxH = constraints.maxHeight - inset;
        var width = maxW;
        var height = width / aspect;
        if (height > maxH) {
          height = maxH;
          width = height * aspect;
        }

        return Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ComparisonSlider(
                      beforeAsset: widget.beforeAsset,
                      afterAsset: widget.afterAsset,
                      fit: BoxFit.cover,
                    ),
                    const Positioned(
                      left: 10,
                      top: 10,
                      child: IgnorePointer(
                        child: _LabelPill(label: 'Antes', filled: false),
                      ),
                    ),
                    const Positioned(
                      right: 10,
                      top: 10,
                      child: IgnorePointer(
                        child: _LabelPill(label: 'Depois', filled: true),
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
}

class _ShowcaseFrame extends StatelessWidget {
  const _ShowcaseFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071433),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF102454),
              Color(0xFF071433),
              Color(0xFF040C22),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              left: -40,
              right: -40,
              height: 280,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.2),
                    radius: 0.9,
                    colors: [
                      Color(0xFF1E4E9A),
                      Color(0x001E4E9A),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              top: 220,
              height: 420,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.85,
                    colors: [
                      Color(0x66168BFF),
                      Color(0x00168BFF),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(child: child),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackButton(onPressed: onBack),
          ),
          Image.asset(
            'assets/branding/logo_lockup_clear.png',
            height: 68,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class _IntroHeadline extends StatelessWidget {
  const _IntroHeadline();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: BrandVisual.title(size: 26, color: Colors.white, height: 1.15),
        children: [
          const TextSpan(text: 'Olhe o que a IA do Editaí\n'),
          TextSpan(
            text: 'pode fazer nas suas fotos',
            style: BrandVisual.title(
              size: 26,
              color: const Color(0xFF5EBEFF),
              height: 1.15,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _LabelPill extends StatelessWidget {
  const _LabelPill({required this.label, required this.filled});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled
            ? BrandVisual.blue
            : const Color(0xFF10213D).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: BrandVisual.text(
            size: 13,
            weight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PrimaryPill extends StatefulWidget {
  const _PrimaryPill({
    required this.label,
    required this.onPressed,
    this.pulse = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool pulse;

  @override
  State<_PrimaryPill> createState() => _PrimaryPillState();
}

class _PrimaryPillState extends State<_PrimaryPill>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulse = _pulse;
    if (pulse == null) return _pill(glow: 0, shine: -1);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final raw = pulse.value;
        final mirrored = raw < 0.5 ? raw * 2 : (1 - raw) * 2;
        return _pill(
          glow: Curves.easeInOut.transform(mirrored),
          shine: raw,
        );
      },
    );
  }

  Widget _pill({required double glow, required double shine}) {
    return Transform.scale(
      scale: 1 + 0.035 * glow,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7EC8FF).withValues(alpha: 0.28 + 0.5 * glow),
                blurRadius: 14 + 26 * glow,
                spreadRadius: 1 + 3 * glow,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4DA8FF), Color(0xFF168BFF)],
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onPressed,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _Sparkle(size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: BrandVisual.text(
                            size: 18,
                            weight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                if (shine >= 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1.6 + 3.2 * shine, 0),
                            end: Alignment(-0.5 + 3.2 * shine, 0),
                            colors: const [
                              Color(0x00FFFFFF),
                              Color(0xAAFFFFFF),
                              Color(0x00FFFFFF),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == index ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ],
    );
  }
}

class _OfferHeader extends StatelessWidget {
  const _OfferHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: _Thumb(
                  asset: 'assets/ai_showcase/fundo_depois.png',
                  size: 72,
                  circular: true,
                ),
              ),
              const Align(
                alignment: Alignment.centerRight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Thumb(
                      asset: 'assets/ai_showcase/pessoas_depois.png',
                      size: 44,
                    ),
                    SizedBox(height: 6),
                    _Thumb(
                      asset: 'assets/ai_showcase/restaurar_depois.png',
                      size: 36,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 78),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _Sparkle(size: 16, color: Colors.white),
                    const SizedBox(height: 4),
                    Text(
                      'Desbloqueie a IA do Editaí',
                      textAlign: TextAlign.center,
                      style: BrandVisual.title(
                        size: 22,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Edite com inteligência artificial\ne transforme suas fotos.',
          textAlign: TextAlign.center,
          style: BrandVisual.text(
            size: 15,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.asset,
    required this.size,
    this.circular = false,
  });

  final String asset;
  final double size;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final radius = circular ? size : 10.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(circular ? size : 10),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: Image.asset(asset, fit: BoxFit.cover),
      ),
    );
  }
}

class _PlanOfferCard extends StatelessWidget {
  const _PlanOfferCard({required this.plan});

  final PlanModel? plan;

  @override
  Widget build(BuildContext context) {
    final credits = plan?.addCredit;
    final price = plan?.price;
    final monthly = plan == null ||
        plan!.durationMonths == null ||
        plan!.durationMonths! <= 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A4A96),
            Color(0xFF0E2C68),
          ],
        ),
        border: Border.all(color: const Color(0xFF6EB6FF).withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF168BFF).withValues(alpha: 0.28),
            blurRadius: 28,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.workspace_premium,
                  color: Color(0xFFF5C542),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    (plan?.name ?? 'Plano Editaí IA').toUpperCase(),
                    textAlign: TextAlign.center,
                    style: BrandVisual.text(
                      size: 13,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: BrandVisual.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      'MAIS POPULAR',
                      style: BrandVisual.text(
                        size: 10,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (price != null && price > 0) ...[
              const SizedBox(height: 14),
              Text(
                'De R\$67',
                style: BrandVisual.text(
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.55),
                ).copyWith(
                  decoration: TextDecoration.lineThrough,
                  decorationColor: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Por apenas',
                style: BrandVisual.text(
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _reais(price),
                      style: BrandVisual.title(size: 42, color: Colors.white),
                    ),
                    if (monthly)
                      TextSpan(
                        text: '/mês',
                        style: BrandVisual.text(
                          size: 18,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (credits != null && credits > 0) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C542),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.toll,
                        color: Color(0xFF10213D),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$credits créditos por mês',
                        style: BrandVisual.text(
                          size: 15,
                          weight: FontWeight.w800,
                          color: const Color(0xFF10213D),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Com a IA do Editaí você pode:',
              style: BrandVisual.text(
                size: 14,
                weight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 10),
            for (final benefit in _benefits) ...[
              _BenefitRow(benefit: benefit),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.white.withValues(alpha: 0.85),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Use seus créditos como quiser nas suas fotos. Sem limites de criatividade.',
                        style: BrandVisual.text(
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefit});

  final ({IconData icon, Color color, String title, String detail}) benefit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: benefit.color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(benefit.icon, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    benefit.title,
                    style: BrandVisual.text(
                      size: 14,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    benefit.detail,
                    style: BrandVisual.text(
                      size: 12,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SparklePainter(color),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..moveTo(center.dx, 0)
      ..quadraticBezierTo(center.dx, center.dy, size.width, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, size.height)
      ..quadraticBezierTo(center.dx, center.dy, 0, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

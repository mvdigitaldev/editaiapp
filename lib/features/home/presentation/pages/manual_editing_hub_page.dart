import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_visual.dart';
import '../../../../core/widgets/brand_blue_wash.dart';
import '../../../editor/beauty_engine/di/beauty_engine_feature_flag_provider.dart';

/// Escolha da ferramenta de edição local. As rotas não mudam.
class ManualEditingHubPage extends ConsumerWidget {
  const ManualEditingHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final beautyEnabledAsync = ref.watch(beautyEngineEnabledProvider);
    final onSurface = isDark ? Colors.white : BrandVisual.navy;

    return Scaffold(
      backgroundColor: isDark ? BrandVisual.navy : Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        foregroundColor: onSurface,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: BrandBlueWash(isDark: isDark)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, kToolbarHeight, 20, 24),
              child: Column(
                children: [
                  Text(
                    'Editar sua foto',
                    textAlign: TextAlign.center,
                    style: BrandVisual.title(size: 28, color: onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Escolha o que deseja fazer e comece agora.',
                    textAlign: TextAlign.center,
                    style: BrandVisual.text(
                      size: 15,
                      color: onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _HubGrid(
                    isDark: isDark,
                    cards: const [
                      _HubTool(
                        title: 'Retoques',
                        description: 'Aparência da pele, ajustes de corpo.',
                        icon: Icons.face_retouching_natural,
                        accent: Color(0xFFFF4D8D),
                        imageAsset: 'assets/home/hub_retoques.png',
                        route: '/beauty-editor',
                      ),
                      _HubTool(
                        title: 'Sem Emenda',
                        description:
                            'Crie montagens de fotos com transições suaves.',
                        icon: Icons.photo_library_outlined,
                        accent: BrandVisual.blue,
                        imageAsset: 'assets/home/hub_emenda.png',
                        route: '/seamless-collage',
                      ),
                      _HubTool(
                        title: 'Edição Básica',
                        description:
                            'Ajuste cor, brilho, contraste nas suas fotos.',
                        icon: Icons.wb_sunny_outlined,
                        accent: Color(0xFF22C55E),
                        imageAsset: 'assets/home/hub_basica.png',
                        route: '/manual-editor',
                      ),
                      _HubTool(
                        title: 'Adicione Filtros',
                        description: 'Escolha o que mais combina com sua foto.',
                        icon: Icons.auto_awesome_outlined,
                        accent: Color(0xFF8B5CF6),
                        imageAsset: 'assets/home/hub_filtros.png',
                        route: '/manual-editor',
                      ),
                    ],
                  ),
                  beautyEnabledAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (enabled) {
                      if (!enabled) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Column(
                          children: [
                            _ExtraLink(
                              title: 'Criar filtro custom',
                              color: onSurface,
                              onTap: () => Navigator.of(context)
                                  .pushNamed('/beauty-preset-creator'),
                            ),
                            _ExtraLink(
                              title: 'Marketplace de filtros',
                              color: onSurface,
                              onTap: () => Navigator.of(context)
                                  .pushNamed('/beauty-preset-marketplace'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubTool {
  const _HubTool({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.route,
    this.imageAsset,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final String route;
  final String? imageAsset;
}

class _HubGrid extends StatelessWidget {
  const _HubGrid({required this.isDark, required this.cards});

  final bool isDark;
  final List<_HubTool> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < cards.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ToolCard(tool: cards[row], isDark: isDark)),
                const SizedBox(width: 12),
                Expanded(
                  child: _ToolCard(tool: cards[row + 1], isDark: isDark),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool, required this.isDark});

  final _HubTool tool;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = Color.alphaBlend(
      tool.accent.withValues(alpha: isDark ? 0.28 : 0.16),
      isDark ? BrandVisual.navy : Colors.white,
    );
    final titleColor = isDark ? Colors.white : BrandVisual.navy;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(tool.route),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? tool.accent.withValues(alpha: 0.4) : Colors.white,
            ),
            boxShadow: [
              BoxShadow(
                color: tool.accent.withValues(alpha: isDark ? 0.22 : 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 58),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ToolArt(tool: tool),
                    const SizedBox(height: 12),
                    Text(
                      tool.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BrandVisual.title(
                        size: 18,
                        height: 1.2,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 14 * 1.3 * 3,
                      child: Text(
                        tool.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: BrandVisual.text(
                          size: 14,
                          height: 1.3,
                          color: titleColor.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tool.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
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

class _ToolArt extends StatelessWidget {
  const _ToolArt({required this.tool});

  final _HubTool tool;

  @override
  Widget build(BuildContext context) {
    final image = tool.imageAsset;
    return SizedBox(
      height: 112,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: image == null
                  ? ColoredBox(
                      color: tool.accent.withValues(alpha: 0.18),
                      child: Icon(tool.icon, size: 48, color: tool.accent),
                    )
                  : Image.asset(image, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tool.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tool.icon, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtraLink extends StatelessWidget {
  const _ExtraLink({
    required this.title,
    required this.color,
    required this.onTap,
  });

  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: BrandVisual.blue,
          minimumSize: const Size(48, 44),
        ),
        child: Text(
          title,
          style: BrandVisual.text(
            size: 15,
            weight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

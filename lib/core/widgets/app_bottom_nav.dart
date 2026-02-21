import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Bottom navigation com 5 itens, mesma distância entre si:
/// 0: Painel, 1: Galeria, 2: Editor (central, borda superior vazada), 3: Modelos, 4: Perfil.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const int indexEditor = 2;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double barHeight = 64;
    const double editorProtrusion = 20;
    const double centralButtonRadius = 28;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // Barra retangular (sem recorte): ícones Painel, Galeria, Modelos e Perfil ficam centralizados dentro dela
        Container(
          height: barHeight + MediaQuery.of(context).padding.bottom,
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.backgroundDark.withOpacity(0.95)
                : AppColors.surfaceLight.withOpacity(0.95),
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.border,
                width: 1,
              ),
            ),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: Icons.dashboard_outlined,
                      label: 'Painel',
                      isSelected: currentIndex == 0,
                      onTap: () => onTap(0),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.photo_library_outlined,
                      label: 'Galeria',
                      isSelected: currentIndex == 1,
                      onTap: () => onTap(1),
                    ),
                  ),
                  // Slot do Editor (label alinhado aos outros; o botão fica por cima)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 28),
                        Text(
                          'Editor',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: currentIndex == indexEditor
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontWeight: currentIndex == indexEditor
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.apps_outlined,
                      label: 'Modelos',
                      isSelected: currentIndex == 3,
                      onTap: () => onTap(3),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.person,
                      label: 'Perfil',
                      isSelected: currentIndex == 4,
                      onTap: () => onTap(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Apenas o Editor: botão um pouco maior e só 12px vazado acima do topo do menu
        Positioned(
          left: 0,
          right: 0,
          top: -editorProtrusion,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onTap(indexEditor),
                customBorder: const CircleBorder(),
                child: Container(
                  width: centralButtonRadius * 2,
                  height: centralButtonRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_fix_high,
                    color: AppColors.textLight,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

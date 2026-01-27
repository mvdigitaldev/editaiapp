import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/bento_card.dart';
import '../../../../core/widgets/progress_indicator.dart';

class PreEvaluationPage extends StatefulWidget {
  final String? initialImagePath;

  const PreEvaluationPage({
    super.key,
    this.initialImagePath,
  });

  @override
  State<PreEvaluationPage> createState() => _PreEvaluationPageState();
}

class _PreEvaluationPageState extends State<PreEvaluationPage> {
  int _currentStep = 0;
  String? _selectedCategory;
  String? _selectedObjective;
  String? _selectedStyle;

  final List<Map<String, dynamic>> _steps = [
    {
      'title': 'O que você quer editar?',
      'subtitle': 'Selecione a categoria para que nossa IA otimize os ajustes.',
      'options': [
        {'icon': Icons.restaurant, 'label': 'Comida', 'value': 'food'},
        {'icon': Icons.face, 'label': 'Pessoa', 'value': 'person'},
        {'icon': Icons.landscape, 'label': 'Paisagem', 'value': 'landscape'},
        {'icon': Icons.inventory_2, 'label': 'Produto', 'value': 'product'},
        {'icon': Icons.auto_awesome, 'label': 'Outro', 'value': 'other', 'subtitle': 'Arquitetura, pets, objetos, etc.'},
      ],
    },
    {
      'title': 'Qual o objetivo da edição?',
      'subtitle': 'Escolha o que você deseja melhorar na imagem.',
      'options': [
        {'icon': Icons.palette, 'label': 'Melhorar cores', 'value': 'enhance_colors'},
        {'icon': Icons.wallpaper, 'label': 'Trocar fundo', 'value': 'replace_background'},
        {'icon': Icons.remove_circle_outline, 'label': 'Remover objetos', 'value': 'remove_objects'},
        {'icon': Icons.zoom_in, 'label': 'Realçar detalhes', 'value': 'enhance_details'},
        {'icon': Icons.wb_sunny, 'label': 'Ajustar iluminação', 'value': 'adjust_lighting'},
      ],
    },
    {
      'title': 'Estilo desejado?',
      'subtitle': 'Como você quer que a imagem final fique?',
      'options': [
        {'icon': Icons.nature, 'label': 'Natural', 'value': 'natural'},
        {'icon': Icons.business_center, 'label': 'Profissional', 'value': 'professional'},
        {'icon': Icons.brush, 'label': 'Artístico', 'value': 'artistic'},
        {'icon': Icons.camera_alt, 'label': 'Realista', 'value': 'realistic'},
      ],
    },
  ];

  void _handleOptionTap(String value) {
    setState(() {
      if (_currentStep == 0) {
        _selectedCategory = value;
      } else if (_currentStep == 1) {
        _selectedObjective = value;
      } else if (_currentStep == 2) {
        _selectedStyle = value;
      }
    });
  }

  void _handleContinue() {
    if (_currentStep < _steps.length - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      // Navigate to AI prompt editor
      Navigator.of(context).pushReplacementNamed(
        '/ai-prompt-editor',
        arguments: widget.initialImagePath,
      );
    }
  }

  void _handleBack() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  String? _getSelectedValue() {
    if (_currentStep == 0) return _selectedCategory;
    if (_currentStep == 1) return _selectedObjective;
    return _selectedStyle;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentStepData = _steps[_currentStep];
    final progress = (_currentStep + 1) / _steps.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _handleBack,
                  ),
                  const Spacer(),
                  Column(
                    children: [
                      Text(
                        'Passo ${_currentStep + 1} de ${_steps.length}',
                        style: AppTextStyles.overline.copyWith(
                          color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AppProgressIndicator(
                progress: progress,
              ),
            ),
            const SizedBox(height: 32),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentStepData['title'] as String,
                      style: AppTextStyles.displaySmall.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      currentStepData['subtitle'] as String,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Options grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: (currentStepData['options'] as List).length,
                      itemBuilder: (context, index) {
                        final option = (currentStepData['options'] as List)[index];
                        final isSelected = _getSelectedValue() == option['value'];

                        if (option['subtitle'] != null) {
                          // Full width option
                          return GridTile(
                            child: BentoCard(
                              icon: option['icon'] as IconData,
                              title: option['label'] as String,
                              subtitle: option['subtitle'] as String?,
                              isSelected: isSelected,
                              onTap: () => _handleOptionTap(option['value'] as String),
                            ),
                          );
                        }

                        return BentoCard(
                          icon: option['icon'] as IconData,
                          title: option['label'] as String,
                          isSelected: isSelected,
                          onTap: () => _handleOptionTap(option['value'] as String),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            // Footer button
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.backgroundDark
                    : AppColors.backgroundLight,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.border,
                  ),
                ),
              ),
              child: AppButton(
                text: 'Continuar',
                onPressed: _getSelectedValue() != null ? _handleContinue : null,
                icon: Icons.arrow_forward,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/progress_indicator.dart';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({super.key});

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _simulateProcessing();
  }

  void _simulateProcessing() async {
    // Simulate processing
    for (int i = 0; i <= 100; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        setState(() {
          _progress = i / 100;
        });
      }
    }

    // Navigate to comparison after processing
    if (mounted) {
      Navigator.of(context).pushReplacementNamed(
        '/comparison',
        arguments: {
          'before': null, // TODO: Get from state
          'after': null, // TODO: Get from state
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 60,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 32),
                // Title
                Text(
                  'Processando sua edição...',
                  style: AppTextStyles.headingLarge.copyWith(
                    color: isDark ? AppColors.textLight : AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Subtitle
                Text(
                  'Nossa IA está trabalhando para criar o melhor resultado',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                // Progress
                AppProgressIndicator(
                  progress: _progress,
                  label: '${(_progress * 100).toInt()}%',
                ),
                const SizedBox(height: 48),
                // Cancel button
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Cancelar',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
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

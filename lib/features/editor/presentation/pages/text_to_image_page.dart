import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/providers/enable_plans_provider.dart';
import '../../../subscription/presentation/pro_plan_invite.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../../core/theme/brand_visual.dart';
import '../../../../core/widgets/brand_blue_wash.dart';
import '../../../../core/utils/aspect_ratio_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/aspect_ratio_selector.dart';
import '../../../../core/widgets/prompt_input_field.dart';
import '../utils/edit_submission_helpers.dart';

class TextToImagePage extends ConsumerStatefulWidget {
  const TextToImagePage({super.key});

  @override
  ConsumerState<TextToImagePage> createState() => _TextToImagePageState();
}

class _TextToImagePageState extends ConsumerState<TextToImagePage> {
  final _promptController = TextEditingController();
  String _selectedAspectRatio = '1:1';
  bool _isLoading = false;

  Future<void> _handleGenerate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isLoading) return;

    final plansOn = ref.read(enablePlansProvider).valueOrNull == true;
    final balance = ref.read(creditsUsageProvider).valueOrNull?.balance ?? 0;
    if (plansOn && balance < 5) {
      await showOutOfAiCreditsOffer(context, ref);
      return;
    }

    final size = getFluxSizeForAspect(_selectedAspectRatio);

    setState(() {
      _isLoading = true;
    });

    try {
      final dio = DioClient();
      final clientRequestId = const Uuid().v4();
      final response = await dio.instance.post<Map<String, dynamic>>(
        '/functions/v1/gerar-imagem-flux',
        data: {
          'client_request_id': clientRequestId,
          'user_prompt': prompt,
          'width': size.width,
          'height': size.height,
        },
      );

      if (!mounted) return;

      if (response.statusCode == 402) {
        setState(() => _isLoading = false);
        await showOutOfAiCreditsOffer(context, ref);
        return;
      }

      final data = response.data;
      final editId = readAcceptedEditId(data);
      final acceptedStatus = readAcceptedStatus(data);
      final acceptedAt = readAcceptedAt(data);

      if (editId == null) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Não foi possível iniciar a geração da imagem. Tente novamente.'),
          ),
        );
        return;
      }

      await trackAcceptedEdit(
        ref,
        editId: editId,
        operationType: 'text_to_image',
        status: acceptedStatus,
        acceptedAt: acceptedAt,
      );
      if (!mounted) return;
      openProcessingPage(
        context,
        editId: editId,
        status: acceptedStatus,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (showStorageLimitFeedback(context, e)) {
        return;
      }
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 402) {
          await showOutOfAiCreditsOffer(context, ref);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Erro ao comunicar com o servidor. Verifique sua conexão e tente novamente.'),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Erro ao comunicar com o servidor. Verifique sua conexão e tente novamente.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : BrandVisual.navy;

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
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
          title: Text(
            'Texto para imagem',
            style: BrandVisual.title(size: 18, color: onSurface),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: BrandBlueWash(isDark: isDark)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: kToolbarHeight),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Descreva a imagem que deseja criar',
                              style: BrandVisual.text(
                                size: 15,
                                color: onSurface.withValues(alpha: 0.62),
                              ),
                            ),
                            const SizedBox(height: 16),
                            PromptInputField(
                              controller: _promptController,
                              maxLines: 6,
                              hintText:
                                  'Ex: Um gato astronauta em Marte, estilo cartoon',
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Proporção da imagem',
                              style:
                                  BrandVisual.title(size: 18, color: onSurface),
                            ),
                            const SizedBox(height: 12),
                            AspectRatioSelector(
                              selected: _selectedAspectRatio,
                              onChanged: (value) {
                                setState(() {
                                  _selectedAspectRatio = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final plansOn =
                              ref.watch(enablePlansProvider).valueOrNull ==
                                  true;
                          final creditsAsync = ref.watch(creditsUsageProvider);
                          final balance =
                              creditsAsync.valueOrNull?.balance ?? 0;
                          final isLoadingCredits = creditsAsync.isLoading;
                          final hasEnoughCredits = !plansOn ||
                              isLoadingCredits ||
                              balance >= 5;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  if (!hasEnoughCredits && !_isLoading) {
                                    await showOutOfAiCreditsOffer(context, ref);
                                  }
                                },
                                behavior: HitTestBehavior.opaque,
                                child: AbsorbPointer(
                                  absorbing: !hasEnoughCredits,
                                  child: AppButton(
                                    text: 'Gerar',
                                    onPressed: hasEnoughCredits
                                        ? _handleGenerate
                                        : null,
                                    icon: Icons.auto_awesome,
                                    isLoading: _isLoading,
                                    width: double.infinity,
                                  ),
                                ),
                              ),
                              if (plansOn && !isLoadingCredits && balance < 5) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Você precisa de 5 créditos. Toque no botão para comprar.',
                                  style: BrandVisual.text(
                                    size: 13,
                                    color: onSurface.withValues(alpha: 0.62),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          );
                        },
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

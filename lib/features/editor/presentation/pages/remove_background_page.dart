import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/providers/enable_plans_provider.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/image_resize_utils.dart';
import '../../../subscription/presentation/pro_plan_invite.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../../core/theme/brand_visual.dart';
import '../../../../core/widgets/brand_blue_wash.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/upload_area.dart';
import '../utils/edit_submission_helpers.dart';

class RemoveBackgroundPage extends ConsumerStatefulWidget {
  const RemoveBackgroundPage({super.key});

  @override
  ConsumerState<RemoveBackgroundPage> createState() =>
      _RemoveBackgroundPageState();
}

class _RemoveBackgroundPageState extends ConsumerState<RemoveBackgroundPage> {
  String? _selectedImagePath;
  bool _isLoading = false;

  Future<void> _handleRemove() async {
    if (_selectedImagePath == null || _isLoading) return;

    final plansOn = ref.read(enablePlansProvider).valueOrNull == true;
    final balance = ref.read(creditsUsageProvider).valueOrNull?.balance ?? 0;
    if (plansOn && balance < 7) {
      await showOutOfAiCreditsOffer(context, ref);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faça login para continuar.')),
        );
        return;
      }

      final result = await resizeAndCompressForEdit(
        inputPath: _selectedImagePath!,
        maxMegapixels: 1.5,
      );
      final storagePath = '${user.id}/inputs/${const Uuid().v4()}.jpg';
      await Supabase.instance.client.storage
          .from(AppConfig.editInputsBucket)
          .upload(storagePath, result.file,
              fileOptions: const FileOptions(upsert: false));
      try {
        await result.file.delete();
      } catch (_) {}

      final dio = DioClient();
      final clientRequestId = const Uuid().v4();
      final response = await dio.instance.post<Map<String, dynamic>>(
        '/functions/v1/remover-fundo-flux',
        data: {
          'client_request_id': clientRequestId,
          'storage_path': storagePath,
        },
      );

      if (!mounted) return;

      final data = response.data;
      final editId = readAcceptedEditId(data);
      final acceptedStatus = readAcceptedStatus(data);
      final acceptedAt = readAcceptedAt(data);

      if (editId == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Não foi possível iniciar a remoção do fundo. Tente novamente.'),
          ),
        );
        return;
      }

      await trackAcceptedEdit(
        ref,
        editId: editId,
        operationType: 'remove_background',
        status: acceptedStatus,
        acceptedAt: acceptedAt,
      );
      if (!mounted) return;
      openProcessingPage(
        context,
        editId: editId,
        beforePath: _selectedImagePath,
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
            'Remover fundo',
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
                              'Selecione uma imagem para remover o fundo',
                              style: BrandVisual.text(
                                size: 15,
                                color: onSurface.withValues(alpha: 0.62),
                              ),
                            ),
                            const SizedBox(height: 16),
                            UploadArea(
                              imagePath: _selectedImagePath,
                              onImageSelected: (File file) {
                                setState(() => _selectedImagePath = file.path);
                              },
                              title: 'Selecione uma imagem',
                              subtitle: 'Toque para carregar',
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
                              balance >= 7;
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
                                    text: 'Remover fundo',
                                    onPressed:
                                        hasEnoughCredits ? _handleRemove : null,
                                    icon: Icons.wallpaper,
                                    width: double.infinity,
                                    isLoading: _isLoading,
                                  ),
                                ),
                              ),
                              if (plansOn && !isLoadingCredits && balance < 7) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Você precisa de 7 créditos. Toque no botão para comprar.',
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

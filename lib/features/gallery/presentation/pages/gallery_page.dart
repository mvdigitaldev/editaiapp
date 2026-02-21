import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/loading_indicator.dart';
import '../../../../core/widgets/error_widget.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../widgets/photo_grid.dart';
import '../providers/gallery_provider.dart';
import '../../domain/usecases/get_user_photos.dart';
import '../../domain/entities/gallery_photo.dart';

class GalleryPage extends ConsumerStatefulWidget {
  /// Quando true, exibe botão voltar no header (ex.: quando a página é aberta por push).
  final bool showBackButton;
  /// Quando true, exibe a barra inferior (não usar quando a página está dentro da MainShellPage).
  final bool showBottomNav;

  const GalleryPage({
    super.key,
    this.showBackButton = true,
    this.showBottomNav = false,
  });

  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  int _currentPage = 0;
  final int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final getUserPhotos = ref.watch(getUserPhotosProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (widget.showBackButton)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    const SizedBox(width: 48),
                  const Spacer(),
                  Text(
                    'Galeria',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.textLight
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Content
            Expanded(
              child: FutureBuilder(
                future: getUserPhotos(
                  limit: _pageSize,
                  offset: _currentPage * _pageSize,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingIndicator(message: 'Carregando fotos...');
                  }

                  if (snapshot.hasError) {
                    return AppErrorWidget(
                      failure: snapshot.error as Failure,
                      onRetry: () => setState(() {}),
                    );
                  }

                  final photos = snapshot.data?.fold(
                    (failure) => <GalleryPhoto>[],
                    (photos) => photos,
                  ) ?? [];

                  if (photos.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 64,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma foto encontrada',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return PhotoGrid(photos: photos);
                },
              ),
            ),
            if (widget.showBottomNav)
              AppBottomNav(
                currentIndex: 1,
                onTap: (_) {},
              ),
          ],
        ),
      ),
    );
  }
}

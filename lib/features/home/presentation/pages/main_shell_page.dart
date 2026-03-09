import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/widgets/ad_banner_widget.dart';
import 'home_page.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../dashboard/presentation/pages/dashboard_page.dart';
import '../../../gallery/presentation/pages/gallery_page.dart';
import '../../../models/presentation/pages/models_page.dart';

class MainShellPage extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainShellPage({
    super.key,
    this.initialIndex = AppBottomNav.indexEditor, // Editor como padrão
  });

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isFree = authState.user?.subscriptionTier.toLowerCase() == 'free';
    final showBanner = !kIsWeb && isFree;

    final pages = [
      const DashboardPage(),
      const GalleryPage(showBackButton: false, showBottomNav: false),
      const HomePage(),
      const ModelsPage(),
      const ProfilePage(),
    ];

    final navBar = AppBottomNav(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
    );

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: showBanner
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AdBannerWidget(),
                navBar,
              ],
            )
          : navBar,
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import 'home_page.dart';
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

  void _goToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardPage(),
      const GalleryPage(showBackButton: false, showBottomNav: false),
      const HomePage(),
      ModelsPage(onOpenEditor: () => _goToTab(AppBottomNav.indexEditor)),
      const ProfilePage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}


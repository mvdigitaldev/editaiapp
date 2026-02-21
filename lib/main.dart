import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/storage/local_storage.dart' as app_storage;
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/register_page.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/editor/presentation/pages/editor_page.dart';
import 'features/gallery/presentation/pages/gallery_page.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'features/editor/presentation/pages/pre_evaluation_page.dart';
import 'features/editor/presentation/pages/ai_prompt_editor_page.dart';
import 'features/editor/presentation/pages/comparison_page.dart';
import 'features/editor/presentation/pages/processing_page.dart';
import 'features/profile/presentation/pages/profile_page.dart';
import 'features/profile/presentation/pages/user_data_page.dart';
import 'features/profile/presentation/pages/affiliate_page.dart';
import 'features/subscription/presentation/pages/subscription_page.dart';
import 'features/subscription/presentation/pages/credits_shop_page.dart';
import 'features/home/presentation/pages/main_shell_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Inicializar Local Storage
  final localStorage = app_storage.LocalStorage();
  await localStorage.init();

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/home': (context) => const MainShellPage(),
        '/editor': (context) => const EditorPage(),
        '/gallery': (context) => const GalleryPage(),
        '/pre-evaluation': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          return PreEvaluationPage(initialImagePath: args as String?);
        },
        '/ai-prompt-editor': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          return AIPromptEditorPage(imagePath: args as String?);
        },
        '/comparison': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, String?>;
          return ComparisonPage(
            beforeImagePath: args['before'],
            afterImagePath: args['after'],
          );
        },
        '/processing': (context) => const ProcessingPage(),
        '/profile': (context) => const ProfilePage(),
        '/user-data': (context) => const UserDataPage(),
        '/affiliate': (context) => const AffiliatePage(),
        '/subscription': (context) => const SubscriptionPage(),
        '/credits-shop': (context) => const CreditsShopPage(),
      },
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    if (authState.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (authState.isAuthenticated) {
      // Usuário autenticado vai para a shell principal; inicia na aba Editor (índice 2).
      return const MainShellPage(initialIndex: 2);
    }

    return const LoginPage();
  }
}

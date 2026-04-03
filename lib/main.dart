import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/config/app_config.dart';
import 'core/navigation/app_navigator.dart';
import 'core/services/ad_service.dart';
import 'core/services/notification_service.dart';
import 'core/widgets/ad_banner_widget.dart';
import 'features/profile/data/datasources/app_settings_datasource.dart';
import 'firebase_options.dart';
import 'core/storage/local_storage.dart' as app_storage;
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/register_page.dart';
import 'features/auth/presentation/pages/reset_password_page.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/editor/presentation/pages/editor_page.dart';
import 'features/gallery/presentation/pages/gallery_page.dart';
import 'features/editor/presentation/pages/pre_evaluation_page.dart';
import 'features/editor/presentation/pages/ai_prompt_editor_page.dart';
import 'features/editor/presentation/pages/comparison_page.dart';
import 'features/editor/presentation/pages/processing_page.dart';
import 'features/editor/presentation/pages/text_to_image_page.dart';
import 'features/editor/presentation/pages/edit_image_page.dart';
import 'features/editor/presentation/pages/create_composition_page.dart';
import 'features/editor/presentation/pages/remove_background_page.dart';
import 'features/editor/presentation/pages/text_to_image_result_page.dart';
import 'features/profile/presentation/pages/profile_page.dart';
import 'features/profile/presentation/pages/user_data_page.dart';
import 'features/profile/presentation/pages/affiliate_page.dart';
import 'features/subscription/presentation/pages/subscription_page.dart';
import 'features/subscription/presentation/pages/credits_shop_page.dart';
import 'features/home/presentation/pages/main_shell_page.dart';
import 'features/subscription/presentation/pages/checkout_webview_page.dart';
import 'features/profile/presentation/pages/payment_history_page.dart';
import 'features/profile/presentation/pages/legal_document_page.dart';
import 'features/profile/presentation/pages/help_center_page.dart';
import 'features/profile/presentation/pages/referral_details_page.dart';
import 'features/dashboard/presentation/pages/credit_history_page.dart';
import 'features/gallery/presentation/pages/edit_detail_page.dart';
import 'features/models/presentation/pages/edit_model_page.dart';
import 'features/models/presentation/pages/edit_model_guided_page.dart';
import 'features/models/presentation/pages/models_by_category_page.dart';
import 'features/models/presentation/pages/admin_categoria_form_page.dart';
import 'features/models/presentation/pages/admin_modelo_form_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Exibir erros de build em vez de tela branca
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Algo deu errado',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  details.exceptionAsString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  // Inicializar locale PT-BR para formatar datas
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR', null);

  // Inicializar Supabase (se falhar, app ainda abre para não ficar tela branca)
  // authFlowType.implicit: redirect de reset de senha usa tokens no hash (funciona no browser)
  // detectSessionInUri: false — tratamos deep link manualmente no AuthWrapper
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        detectSessionInUri: false,
      ),
    );
  } catch (e, st) {
    debugPrint('[Editai] Erro ao inicializar Supabase: $e');
    debugPrint(st.toString());
  }

  // Inicializar Local Storage
  try {
    final localStorage = app_storage.LocalStorage();
    await localStorage.init();
  } catch (e) {
    debugPrint('[Editai] Erro ao inicializar LocalStorage: $e');
  }

  // AdMob: inicializar apenas em mobile
  AdService? adServiceInstance;
  if (!kIsWeb) {
    try {
      await MobileAds.instance.initialize();
      adServiceInstance = AdService(AppSettingsDataSourceImpl(Supabase.instance.client));
      unawaited(adServiceInstance.preloadInterstitial());
    } catch (e) {
      debugPrint('[Editai] AdMob init: $e');
    }
  }

  // Push notifications: não bloquear abertura do app — inicializar em background
  runApp(
    ProviderScope(
      overrides: adServiceInstance != null
          ? [adServiceProvider.overrideWithValue(adServiceInstance)]
          : [],
      child: MyApp(navigatorKey: appNavigatorKey),
    ),
  );

  if (!kIsWeb) {
    NotificationService().setNavigatorKey(appNavigatorKey);
    Future<void>.microtask(() async {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        await NotificationService().initialize();
      } catch (e) {
        debugPrint('[Editai] Firebase/Notification init: $e');
      }
    });
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key, this.navigatorKey});
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      navigatorKey: navigatorKey,
      title: AppConfig.appName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/reset-password': (context) => const ResetPasswordPage(),
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
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>?;
          return ComparisonPage(
            editId: args?['editId'] as String?,
            beforeImagePath: args?['before'] as String?,
            afterImagePath: args?['after'] as String?,
            afterImageUrl: args?['afterUrl'] as String?,
          );
        },
        '/text-to-image': (context) => const TextToImagePage(),
        '/edit-image': (context) => const EditImagePage(),
        '/create-composition': (context) => const CreateCompositionPage(),
        '/remove-background': (context) => const RemoveBackgroundPage(),
        '/edit-model': (context) => const EditModelPage(),
        '/edit-model-guided': (context) => const EditModelGuidedPage(),
        '/models-by-category': (context) => const ModelsByCategoryPage(),
        '/admin/categoria/form': (context) => const AdminCategoriaFormPage(),
        '/admin/modelo/form': (context) => const AdminModeloFormPage(),
        '/text-to-image-result': (context) => const TextToImageResultPage(),
        '/processing': (context) => const ProcessingPage(),
        '/profile': (context) => const ProfilePage(),
        '/user-data': (context) => const UserDataPage(),
        '/affiliate': (context) => const AffiliatePage(),
        '/subscription': (context) => const SubscriptionPage(),
        '/credits-shop': (context) => const CreditsShopPage(),
        '/checkout': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as String;
          return CheckoutWebViewPage(url: args);
        },
        '/payment-history': (context) => const PaymentHistoryPage(),
        '/legal-document': (context) {
          final slug = ModalRoute.of(context)!.settings.arguments as String;
          return LegalDocumentPage(slug: slug);
        },
        '/help-center': (context) => const HelpCenterPage(),
        '/credit-history': (context) => const CreditHistoryPage(),
        '/edit-detail': (context) {
          final editId = ModalRoute.of(context)!.settings.arguments as String?;
          return EditDetailPage(editId: editId ?? '');
        },
        '/referral-details': (context) => const ReferralDetailsPage(),
      },
    );
  }
}

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  bool _loadingTimedOut = false;
  Timer? _loadingTimer;

  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Web: trocar code por sessão quando usuário volta do link de recuperação de senha
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleAuthCallback());
    } else {
      // Mobile: tratar deep link manualmente (editai:// ou Universal Links)
      _initDeepLinks();
    }
  }

  void _initDeepLinks() {
    final appLinks = AppLinks();
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
    _linkSubscription = appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  Future<void> _handleDeepLink(Uri uri) async {
    final path = uri.path;
    if (!path.contains('reset-password')) return;

    try {
      final code = uri.queryParameters['code'];
      final hasHash = uri.fragment.isNotEmpty;

      if (code != null && code.isNotEmpty) {
        await Supabase.instance.client.auth.exchangeCodeForSession(code);
      } else if (hasHash) {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      } else {
        return;
      }

      if (!mounted) return;
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/reset-password',
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      debugPrint('[Editai] Erro ao processar deep link: $e');
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _loadingTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleAuthCallback() async {
    final code = Uri.base.queryParameters['code'];
    if (code == null || code.isEmpty) return;
    try {
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
      // AuthNotifier pode detectar passwordRecovery; se não, navegar manualmente
      if (!mounted) return;
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/reset-password',
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      debugPrint('[Editai] Erro ao trocar code por sessão: $e');
    }
  }

  static const _loadingTimeoutDuration = Duration(seconds: 12);

  void _startLoadingTimeout() {
    if (_loadingTimer != null && _loadingTimer!.isActive) return;
    _loadingTimer = Timer(_loadingTimeoutDuration, () {
      if (!mounted) return;
      if (ref.read(authStateProvider).isLoading) {
        setState(() => _loadingTimedOut = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    if (authState.isLoading) {
      _startLoadingTimeout();
      if (_loadingTimedOut) {
        return const LoginPage();
      }
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Carregando...',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (authState.isAuthenticated) {
      return const MainShellPage(initialIndex: 2);
    }

    return const LoginPage();
  }
}

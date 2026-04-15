import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[Editai] Mensagem em background: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FirebaseMessaging? _firebaseMessaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialized = false;
  String? _currentToken;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _backgroundSubscription;
  final Set<String> _processedMessages = {};

  static const String _channelId = 'editaiapp_notifications';
  static const String _channelName = 'Editai Notificacoes';

  FirebaseMessaging get _messaging {
    final messaging = _firebaseMessaging;
    if (messaging == null) {
      throw StateError('FirebaseMessaging not initialized');
    }
    return messaging;
  }

  void setNavigatorKey(GlobalKey<NavigatorState>? key) {
    _navigatorKey = key;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('[Editai] Iniciando NotificationService...');

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseMessaging ??= FirebaseMessaging.instance;

      await _initializeLocalNotifications();
      await _requestPermissions();
      if (Platform.isIOS) {
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      await _setupMessageHandlers();

      try {
        await _getAndSaveToken();
      } catch (_) {
        try {
          final token = await _firebaseMessaging?.getToken();
          if (token != null && token.isNotEmpty) _currentToken = token;
        } catch (_) {}
      }

      _messaging.onTokenRefresh.listen(_saveTokenToSupabase);
      _initialized = true;
      debugPrint('[Editai] NotificationService inicializado');
    } catch (e, st) {
      debugPrint('[Editai] Erro ao inicializar NotificationService: $e $st');
      _initialized = true;
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Notificacoes do app Editai',
            importance: Importance.high,
          ));
    }
  }

  Future<void> _requestPermissions() async {
    try {
      if (Platform.isIOS) {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      } else if (Platform.isAndroid) {
        final androidPlugin =
            _localNotifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
        await _messaging.requestPermission();
      }
    } catch (e) {
      debugPrint('[Editai] Erro permissoes: $e');
    }
  }

  Future<void> _setupMessageHandlers() async {
    await _foregroundSubscription?.cancel();
    await _backgroundSubscription?.cancel();
    _foregroundSubscription =
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _backgroundSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _handleBackgroundMessage(initialMessage);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  Future<void> _getAndSaveToken() async {
    if (Firebase.apps.isEmpty) return;
    if (Platform.isIOS) await _waitForAPNSToken();
    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      _currentToken = token;
      await _saveTokenToSupabase(token);
    }
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final platform = Platform.isIOS ? 'ios' : 'android';
      await Supabase.instance.client.rpc('save_device_token', params: {
        'p_token': token,
        'p_platform': platform,
      });
      debugPrint('[Editai] Token FCM salvo no Supabase');
    } catch (e) {
      debugPrint('[Editai] Erro ao salvar token: $e');
      await Future.delayed(const Duration(seconds: 3));
      try {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId == null) return;
        final platform = Platform.isIOS ? 'ios' : 'android';
        await Supabase.instance.client.rpc('save_device_token', params: {
          'p_token': token,
          'p_platform': platform,
        });
      } catch (_) {}
    }
  }

  Future<void> removeToken() async {
    try {
      if (_currentToken == null) return;
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('token', _currentToken!);
      _currentToken = null;
      debugPrint('[Editai] Token removido do Supabase');
    } catch (e) {
      debugPrint('[Editai] Erro ao remover token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final messageId = message.messageId ?? message.hashCode.toString();
    if (_processedMessages.contains(messageId)) return;
    _processedMessages.add(messageId);
    if (_processedMessages.length > 100) {
      final toRemove =
          _processedMessages.take(_processedMessages.length - 100).toList();
      _processedMessages.removeAll(toRemove);
    }
    _showLocalNotification(message);
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    _processNotificationDeepLink(message.data);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    String title;
    String body;
    final notification = message.notification;
    if (notification != null) {
      title = notification.title ?? '';
      body = notification.body ?? '';
    } else {
      final data = message.data;
      title = data['title'] as String? ?? 'Editai';
      body = data['body'] as String? ?? '';
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Notificacoes do app Editai',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      details,
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    try {
      if (response.payload != null && response.payload!.isNotEmpty) {
        try {
          final data = jsonDecode(response.payload!);
          if (data is Map<String, dynamic>) {
            _processNotificationDeepLink(data);
            return;
          }
        } catch (_) {}
      }
      _processNotificationDeepLink({'deep_link': '/home'});
    } catch (_) {
      _processNotificationDeepLink({'deep_link': '/home'});
    }
  }

  void _processNotificationDeepLink(Map<String, dynamic> data) {
    try {
      final route = _resolveNotificationRoute(data);
      if (route == null || route.isEmpty) return;
      final key = _navigatorKey;
      if (key?.currentState == null) return;
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          key?.currentState?.pushNamed(
            route,
            arguments: _buildNotificationArguments(route, data),
          );
        } catch (e) {
          debugPrint('[Editai] Erro ao navegar para $route: $e');
        }
      });
    } catch (e) {
      debugPrint('[Editai] Erro ao processar deep link: $e');
    }
  }

  String? _resolveNotificationRoute(Map<String, dynamic> data) {
    final explicitRoute =
        (data['route'] as String?) ?? (data['deep_link'] as String?);
    if (explicitRoute != null && explicitRoute.isNotEmpty) {
      return explicitRoute;
    }

    final editId = (data['edit_id'] as String?) ?? (data['editId'] as String?);
    final status = data['status'] as String?;
    if (editId == null || editId.isEmpty) return null;
    if (status == 'failed') return '/edit-detail';
    return '/comparison';
  }

  Object? _buildNotificationArguments(
    String route,
    Map<String, dynamic> data,
  ) {
    final editId = (data['edit_id'] as String?) ?? (data['editId'] as String?);
    if (editId == null || editId.isEmpty) return null;

    if (route == '/comparison') {
      return <String, dynamic>{'editId': editId};
    }

    if (route == '/edit-detail') {
      return editId;
    }

    return null;
  }

  Future<void> _waitForAPNSToken() async {
    if (!Platform.isIOS) return;
    const maxAttempts = 60;
    const delayMs = 500;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
          return;
        }
      } catch (_) {}
      if (i < maxAttempts - 1) {
        await Future.delayed(
            Duration(milliseconds: i < 10 ? delayMs : delayMs * 2));
      }
    }
  }

  Future<void> refreshToken() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseMessaging ??= FirebaseMessaging.instance;

      if (Platform.isIOS) await _waitForAPNSToken();
      String? token;
      try {
        token = await _messaging.getToken();
      } catch (e) {
        if (e.toString().contains('apns-token-not-set')) {
          await Future.delayed(const Duration(seconds: 2));
          final apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null) {
            await Future.delayed(const Duration(milliseconds: 500));
            token = await _messaging.getToken();
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        await Future.delayed(const Duration(milliseconds: 1000));
        await _saveTokenToSupabase(token);
      }
    } catch (e) {
      debugPrint('[Editai] Erro refreshToken: $e');
      await Future.delayed(const Duration(seconds: 5));
      try {
        if (_firebaseMessaging == null) return;
        if (Platform.isIOS) await _waitForAPNSToken();
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          _currentToken = token;
          await Future.delayed(const Duration(milliseconds: 1000));
          await _saveTokenToSupabase(token);
        }
      } catch (_) {}
    }
  }

  String? get currentToken => _currentToken;
  bool get isInitialized => _initialized;
}

import 'package:flutter/material.dart';

/// Stub for web - push notifications not supported.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  void setNavigatorKey(GlobalKey<NavigatorState>? key) {}
  Future<void> initialize() async {}
  Future<void> refreshToken() async {}
  Future<void> removeToken() async {}

  bool get isInitialized => true;
  String? get currentToken => null;
}

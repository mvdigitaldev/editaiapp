import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/active_edits_provider.dart';

class ActiveEditsCoordinator extends ConsumerStatefulWidget {
  const ActiveEditsCoordinator({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<ActiveEditsCoordinator> createState() =>
      _ActiveEditsCoordinatorState();
}

class _ActiveEditsCoordinatorState
    extends ConsumerState<ActiveEditsCoordinator> with WidgetsBindingObserver {
  String? _handledUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(activeEditsProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        notifier.setForeground(true);
        notifier.syncNow();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        notifier.setForeground(false);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final userId = authState.user?.id;

    if (userId != _handledUserId) {
      _handledUserId = userId;
      Future<void>.microtask(() async {
        if (!mounted) return;
        await ref.read(activeEditsProvider.notifier).handleAuthChanged(userId);
      });
    }

    return widget.child;
  }
}

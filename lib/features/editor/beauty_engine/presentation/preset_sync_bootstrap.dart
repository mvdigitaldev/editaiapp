import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../di/beauty_engine_providers.dart';

/// Dispara sync de presets quando o usuário autentica (Sprint 23).
class PresetSyncBootstrap extends ConsumerStatefulWidget {
  const PresetSyncBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PresetSyncBootstrap> createState() => _PresetSyncBootstrapState();
}

class _PresetSyncBootstrapState extends ConsumerState<PresetSyncBootstrap> {
  String? _lastSyncedUserId;
  bool _syncing = false;

  Future<void> _syncIfNeeded(String? userId) async {
    if (userId == null || _syncing || _lastSyncedUserId == userId) {
      return;
    }

    _syncing = true;
    try {
      await ref.read(beautyPresetRepositoryProvider).syncWithRemote();
      _lastSyncedUserId = userId;
      ref.invalidate(userBeautyPresetsProvider);
      ref.invalidate(allBeautyPresetsProvider);
      ref.invalidate(marketplacePresetsProvider);
    } catch (_) {
      // Sync falhou — presets locais continuam disponíveis.
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      final userId = next.user?.id;
      if (next.isAuthenticated && userId != null) {
        if (previous?.user?.id != userId || previous?.isAuthenticated != true) {
          _syncIfNeeded(userId);
        }
      } else {
        _lastSyncedUserId = null;
      }
    });

    final auth = ref.watch(authStateProvider);
    if (auth.isAuthenticated && auth.user?.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncIfNeeded(auth.user!.id);
      });
    }

    return widget.child;
  }
}

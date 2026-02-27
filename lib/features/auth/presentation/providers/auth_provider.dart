import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:editaiapp/core/services/notification_service.dart';
import '../../data/datasources/auth_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/delete_account.dart';
import '../../domain/usecases/get_current_user.dart';
import '../../domain/usecases/sign_in.dart';
import '../../domain/usecases/sign_out.dart';
import '../../domain/usecases/sign_up.dart';
import '../../domain/usecases/update_password.dart';
import '../../domain/usecases/update_profile.dart';
import '../../domain/entities/user.dart' as domain;

// Providers
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authDataSourceProvider = Provider<AuthDataSource>((ref) {
  return AuthDataSourceImpl(ref.watch(supabaseClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authDataSourceProvider));
});

final signInProvider = Provider<SignIn>((ref) {
  return SignIn(ref.watch(authRepositoryProvider));
});

final signUpProvider = Provider<SignUp>((ref) {
  return SignUp(ref.watch(authRepositoryProvider));
});

final signOutProvider = Provider<SignOut>((ref) {
  return SignOut(ref.watch(authRepositoryProvider));
});

final getCurrentUserProvider = Provider<GetCurrentUser>((ref) {
  return GetCurrentUser(ref.watch(authRepositoryProvider));
});

final updateProfileProvider = Provider<UpdateProfile>((ref) {
  return UpdateProfile(ref.watch(authRepositoryProvider));
});

final updatePasswordProvider = Provider<UpdatePassword>((ref) {
  return UpdatePassword(ref.watch(authRepositoryProvider));
});

final deleteAccountProvider = Provider<DeleteAccount>((ref) {
  return DeleteAccount(ref.watch(authRepositoryProvider));
});

// State Provider
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(ref.watch(getCurrentUserProvider));
  ref.onDispose(() => notifier.cancelAuthListener());
  return notifier;
});

// State
class AuthState {
  final domain.User? user;
  final bool isLoading;
  final bool isAuthenticated;

  AuthState({
    this.user,
    this.isLoading = false,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    domain.User? user,
    bool? isLoading,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

// Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final GetCurrentUser _getCurrentUser;
  StreamSubscription<dynamic>? _authSubscription;

  AuthNotifier(this._getCurrentUser) : super(AuthState()) {
    checkAuth();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        if (!kIsWeb) {
          if (data.session != null) {
            try {
              final ns = NotificationService();
              if (!ns.isInitialized) await ns.initialize();
              await ns.refreshToken();
            } catch (_) {}
          } else {
            try {
              await NotificationService().removeToken();
            } catch (_) {}
          }
        }
        if (event == AuthChangeEvent.signedOut ||
            event == AuthChangeEvent.userDeleted ||
            event == AuthChangeEvent.tokenRefreshed && data.session == null) {
          checkAuth();
        }
      },
    );
  }

  void cancelAuthListener() {
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  Future<void> checkAuth() async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _getCurrentUser();
      result.fold(
        (failure) {
          state = state.copyWith(
            isLoading: false,
            isAuthenticated: false,
          );
        },
        (user) {
          state = state.copyWith(
            user: user,
            isLoading: false,
            isAuthenticated: user != null,
          );
        },
      );
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Auth] checkAuth error: $e\n$st');
      }
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
      );
    }
  }

  void setUser(domain.User? user) {
    state = state.copyWith(
      user: user,
      isAuthenticated: user != null,
    );
  }
}

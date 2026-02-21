import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/failures.dart';
import '../models/user_model.dart';

abstract class AuthDataSource {
  Future<UserModel> signIn({
    required String email,
    required String password,
  });

  Future<UserModel> signUp({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> signOut();

  Future<UserModel?> getCurrentUser();

  Future<void> resetPassword(String email);

  Future<UserModel> updateProfile({String? displayName, String? avatarUrl});

  Future<void> updatePassword(String newPassword);

  Future<void> deleteAccount();
}

class AuthDataSourceImpl implements AuthDataSource {
  final SupabaseClient _supabase;

  AuthDataSourceImpl(this._supabase);

  @override
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Usuário não encontrado');
      }

      return await _getUserProfile(response.user!.id);
    } catch (e) {
      throw AuthFailure(message: e.toString());
    }
  }

  @override
  Future<UserModel> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      );

      if (response.user == null) {
        throw Exception('Falha ao criar usuário');
      }

      // Perfil é criado pelo trigger handle_new_user em public.users; leitura via view user_profiles
      return await _getUserProfile(response.user!.id);
    } catch (e) {
      throw AuthFailure(message: e.toString());
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      throw AuthFailure(message: e.toString());
    }
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      try {
        return await _getUserProfile(user.id);
      } catch (_) {
        await _supabase.auth.signOut();
        rethrow;
      }
    } catch (e) {
      throw AuthFailure(message: e.toString());
    }
  }

  @override
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      throw AuthFailure(message: e.toString());
    }
  }

  @override
  Future<UserModel> updateProfile({String? displayName, String? avatarUrl}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw AuthFailure(message: 'Usuário não autenticado');

      final data = <String, dynamic>{};
      if (displayName != null) data['display_name'] = displayName;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;
      if (data.isNotEmpty) {
        await _supabase.auth.updateUser(UserAttributes(data: data));
      }

      final updates = <String, dynamic>{};
      if (displayName != null) updates['name'] = displayName;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (updates.isNotEmpty) {
        await _supabase.from('users').update(updates).eq('id', user.id);
      }

      return await _getUserProfile(user.id);
    } catch (e) {
      throw AuthFailure(message: e.toString());
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw AuthFailure(message: e.toString());
    }
  }

  @override
  Future<void> deleteAccount() async {
    // deleteUser() existe apenas na API admin (service_role), não no client.
    // Exclusão real pode ser feita via Edge Function ou painel; aqui retornamos falha informativa.
    throw AuthFailure(
      message: 'Exclusão de conta deve ser solicitada ao suporte ou pelo painel.',
    );
  }

  Future<UserModel> _getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromJson(response);
    } catch (e) {
      throw AuthFailure(message: 'Perfil não encontrado');
    }
  }
}

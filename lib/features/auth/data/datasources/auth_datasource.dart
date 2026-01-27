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

      // Criar perfil do usuário
      await _createUserProfile(
        response.user!.id,
        email: email,
        displayName: displayName,
      );

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

      return await _getUserProfile(user.id);
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

  Future<UserModel> _getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromJson(response);
    } catch (e) {
      // Se o perfil não existe, criar um básico
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _createUserProfile(userId, email: user.email);
        return UserModel(
          id: userId,
          email: user.email,
          subscriptionTier: 'free',
        );
      }
      throw AuthFailure(message: 'Perfil não encontrado');
    }
  }

  Future<void> _createUserProfile(
    String userId, {
    String? email,
    String? displayName,
  }) async {
    try {
      await _supabase.from('user_profiles').insert({
        'id': userId,
        'email': email,
        'display_name': displayName,
        'subscription_tier': 'free',
      });
    } catch (e) {
      // Ignorar se já existe
    }
  }
}
